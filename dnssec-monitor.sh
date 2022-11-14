#!/usr/bin/env bash
# dnssec-monitor.sh
# monitor named log output for CDS published string
# run update.sh with domain
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [[ ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} == "notloaded" || ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} -eq 0 ]]; then
  # shellcheck disable=SC1091
  . "/etc/cme/dnssec-monitor.env"
fi

# shellcheck disable=SC1091
. "${DIR}/lib.sh"

files="/var/log/named/ddns /var/log/named/default /var/log/named/named.run"
empty_ds_regex='zone (.*)/IN/(.*) \('
# shellcheck disable=SC2153
readarray -td: views <<<"${VIEWS}"

# clean ds process files which stop repeated additions via nsupdate for the same domain within a given time period
if [[ $1 == '--clean' ]]; then
  log "monitor running on $$ to clean dsprocess locks"
  function trap_exit() {
    log "terminating dsprocess monitor on PID:$$"
    exit 0
  }

  trap "trap_exit" SIGINT SIGHUP 15

  shopt -s extglob
  while (true); do
    # shellcheck disable=SC2068
    for view in ${views[@]}; do
      for dsprocess in "${DSPROCESS_PATH}/${view}/"*.dsprocess; do
        if [ ! -f "$dsprocess" ]; then
          continue
        fi
        if [[ $(date -r "$dsprocess" "+%s") -lt $(($(date +%s) - 30)) ]]; then
          locked_domain=$(basename "$dsprocess")
          log "removing dsprocess lock for ${locked_domain//\.dsprocess/}/${view} ${dsprocess}"
          rm "$dsprocess"
        fi
      done
    done
    sleep 5
  done
fi

if [[ $1 == '--init' ]]; then
  log "monitor running on $$ to initalise DS keys"
  function trap_exit() {
    log "terminating initalisation of DS keys"
    exit 1
  }

  # shellcheck disable=SC2068
  for view in ${views[@]}; do
    for file in /var/cache/bind/keys/"${view}"/*.state; do
      key_path_prefix="/var/cache/bind/keys/${view}/K"
      key="${file//$key_path_prefix/}"
      key="${key//\.state/}"
      readarray -td '.' domain_parts < <(printf "%s" "$key")
      readarray -td '' array_reversed < <(
        ((${#domain_parts[@]})) && printf '%s\0' "${domain_parts[@]}" | tac -s ''
      )
      unset 'array_reversed[0]'
      readarray -td '' domain_parts < <(
        ((${#array_reversed[@]})) && printf '%s\0' "${array_reversed[@]}" | tac -s ''
      )

      ifsbak=$IFS
      IFS=. domain=${domain_parts[*]}
      IFS=$ifsbak

      if [[ ! -f "${DSPROCESS_PATH}/${view}/${domain}.dsprocess" ]]; then
        touch "${DSPROCESS_PATH}/${view}/${domain}.dsprocess"
        log "domain: ${domain} view:${view}"
        log "thawing domain: ${domain}"
        rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" freeze "${domain}" in "${view}"
        rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" sync -clean "${domain}" in "${view}"
        rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" thaw "${domain}" in "${view}"
      fi
    done
  done

  # iterate views
  # iterate keys
  # create domain env
  # check key has no successor
  #

  log "monitor (initialise keys) terminating on PID:$$"
  exit 0
fi

# stop repeated additions via nsupdate as views are handled in the same scope as the main process
if [[ $1 == '--monitor-external' ]]; then
  log "monitor running on $$ for external CDS/KSK publish events"
  function trap_exit() {
    log "terminating external CDS check on PID:$$"
    exit 0
  }

  while IFS= read -r line; do
    readarray -td: ext_dns <<<"$line"
    ds="$(dig "@${NS_SERVER}" +short "${ext_dns[0]}" DS)"
    if [[ "$ds" != "${ext_dns[1]}" ]]; then
      "${DIR}/update.sh" "${ext_dns[0]}"
    fi
  done <"$EXTERNAL_DOMAIN_LIST"

  trap "trap_exit" SIGINT SIGHUP 15

  shopt -s extglob
  while (true); do
    if [[ -n $retry && $retry -gt $(date +%s) ]]; then
      sleep 5
      continue
    fi

    start=$(date +%s)
    retry=$((start + EXTERNAL_REFRESH))
    for dsprocess in "${DSPROCESS_PATH}/"*.dsprocess; do
      if [ ! -f "$dsprocess" ]; then
        sleep 5
        continue
      fi
      if [[ $(date -r "$dsprocess" "+%s") -lt $(($(date +%s) - 60)) ]]; then
        locked_domain=$(basename "$dsprocess")
        log "removing dsprocess lock for ${locked_domain//\.dsprocess/}"
        rm "$dsprocess"
      fi
    done
    sleep 5
  done
fi

function trap_exit() {
  if [[ -n $monitor_pid && -n $(ps -p "$monitor_pid") ]]; then
    log "monitor terminating on PID:$monitor_pid"
    kill -1 "$monitor_pid"
    wait "$monitor_pid"
  fi
  if [[ -n $tail_pid && -n $(ps -p "$tail_pid") ]]; then
    kill -1 "$tail_pid"
    wait "$tail_pid"
  fi
  exit 0
}

log "monitor running on $$ for CDS/KSK publish events"
# if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
# print config
log "WORKING_DIR ............ : ${DIR}"
log "NS_SERVER .............. : ${NS_SERVER}"
log "DATA_PATH .............. : ${DATA_PATH}"
log "DSPROCESS_PATH ......... : ${DSPROCESS_PATH}"
log "CONF_PATH .............. : ${CONF_PATH}"
log "BIND_LOG_PATH .......... : ${BIND_LOG_PATH}"
log "KEY_PATH ............... : ${KEY_PATH}"
log "CME_DNSSEC_MONITOR_DEBUG : ${CME_DNSSEC_MONITOR_DEBUG}"
log "LOGGER_FLAGS ........... : ${LOGGER_FLAGS}"
log "MONITORING BIND LOGS ... : ${files}"
log "VIEWS .................. : ${views[*]}"

declare ip_addr
declare ns_server
declare domain
declare ttl
declare view
declare record
view_config_check "${views[@]}"

trap "trap_exit" SIGINT SIGHUP 15

LOGGER_FLAGS=${LOGGER_FLAGS} "${DIR}/dnssec-monitor.sh" --clean &

# run once and add all DS keys, regardless
LOGGER_FLAGS=${LOGGER_FLAGS} "${DIR}/dnssec-monitor.sh" --init &

declare -i monitor_pid=$!
declare -i key_found=0

# main monitoring/update
(
  # shellcheck disable=SC2086
  tail -n0 -f $files | stdbuf -oL grep '.*' |
    while IFS= read -r line; do
      # example
      # Nov 11 17:25:06 ninja named[3260031]: 11-Nov-2022 17:25:06.474 general: notice: zone prod.node.flipkick.media/IN/internals-master (signed): checkds: empty DS response from 192.168.88.254#53
      if grep -P '.*checkds: empty DS response.*' <<<"$line"; then
        # capture view from message
        if [[ $line =~ $empty_ds_regex ]]; then
          domain=${BASH_REMATCH[1]}
          view=${BASH_REMATCH[2]}

          view_var="${view^^}"
          iface_var="${view_var//-/_}_IFACE"
          iface=${!iface_var}
          ns_server_var="${view_var//-/_}_NS_SERVER"
          ns_server=${!ns_server_var}
          key_var="${view_var//-/_}_KEY_NAME"
          key_name="${!key_var}"
          key_name_var="${key_name^^}"
          key_name_var="${key_name_var//-/_}"
          iface_name=$(route | tail -n-1 | awk '{print $8}')
          ip_addr="${!iface_var}"
          key="${!key_name_var}"

          log "view_var ....: ${view_var}"
          log "view.........: ${view}"
          log "key_var .....: ${key_var}"
          log "key_name ....: ${key_name}"
          log "key_name_var : ${key_name_var}"
          log "key .........: ${key}"
          log "iface_var ...: ${iface_var}"
          log "iface_name...: ${iface_name}"
          log "iface........: ${iface}"
          log "ip_addr .....: ${ip_addr}"
          log "ns_server....: ${ns_server}"
          log "CONF_PATH....: ${CONF_PATH}"

          log "handling empty DS response: domain:${domain} view:${view}"
          "${DIR}/init" "${ip_addr}" "${ns_server}" "${domain}" 60 "${view}"
        fi
      fi

      # example
      # line='04-Jun-2022 07:12:02.164 dnssec: info: DNSKEY node.flipkick.media/ECDSAP384SHA384/29885 (KSK) is now published'
      if grep -P '.*info: DNSKEY.*\(KSK\).*published.*' <<<"$line"; then
        log ""
        key_found=0
        domain=$(awk '{print $6}' <<<"${line//\// }")
        A="00000"
        B="$(awk '{print $8}' <<<"${line//\// }")"
        #key_id="$(echo "${A:0:-${#B}}$B")"
        key_id="${A:0:-${#B}}$B"
        # shellcheck disable=SC2068
        for view in ${views[@]}; do
          key_file="/var/cache/bind/keys/${view}/K${domain}.+014+${key_id}.key"
          log "checking for key: ${key_file}"
          if [[ -f $key_file ]]; then
            key_found=1
            log "KSK Published! domain:${domain} key_id:${key_id} view:${view}"
            if [[ ! -f "${DSPROCESS_PATH}/${view}/${domain}.dsprocess" ]]; then
              touch "${DSPROCESS_PATH}/${view}/${domain}.dsprocess"
              "${DIR}/add" ${domain} ${key_id} ${view}
              break
            fi
          fi
        done
        if [[ $key_found -gt 0 ]]; then
          log "KSK Published but key was not found in any view! domain:${domain} view:${view} key:K${domain}.+014+${key_id}.key"
        fi
      fi
      # example
      # line='04-Jun-2022 12:00:07.686 general: info: CDS for key node.flipkick.media/ECDSAP384SHA384/16073 is now published'
      if grep -P '.*info: CDS for key.*published.*' <<<"$line"; then
        log ""
        key_found=0
        domain=$(awk '{print $8}' <<<"${line//\// }")
        A="00000"
        B="$(awk '{print $10}' <<<"${line//\// }")"
        #key_id="$(echo "${A:0:-${#B}}$B")"
        key_id="${A:0:-${#B}}$B"
        log "CDS key_id:$key_id"

        # locate view using domain and key id
        for view; do
          key_file="/var/cache/bind/keys/${view}/K${domain}.+014+${key_id}.key"
          if [[ -f $key_file ]]; then
            key_found=1
            log "CDS Published! domain:${domain} key: ${key_id} view:${view}"
            if [[ ! -f "${DSPROCESS_PATH}/${view}/${domain}.dsprocess" ]]; then
              touch "${DSPROCESS_PATH}/${view}/${domain}.dsprocess"
              "${DIR}/update" $domain $key_id $view
            fi
          fi
        done
        if [[ $key_found -eq 0 ]]; then
          log "CDS Published but key was not found! domain:${domain} view:${view} key:K${domain}.+014+${key_id}.key"
        fi
      fi
    done
) &
tail_pid=$!
wait $tail_pid
