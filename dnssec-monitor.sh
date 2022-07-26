#!/usr/bin/env bash
# dnssec-monitor.sh
# monitor named log output for CDS published string
# run update.sh with domain

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export VIEWS=''

if [[ ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} == "notloaded" || ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} -eq 0 ]]; then
  # shellcheck disable=SC1091
  . "/etc/cme/dnssec-monitor.env"
fi
# shellcheck disable=SC1091
. "${DIR}/lib.sh"

# stop repeated additions via nsupdate as views are handled in the same scope as the main process
if [[ $1 == '--clean' ]]; then
  log "monitor running on $$ to clean dsprocess locks"
  function trap_exit() {
    log "terminating dsprocess monitor on PID:$$"
    exit 0
  }

  trap "trap_exit" SIGINT SIGHUP 15

  shopt -s extglob
  while (true); do
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

if [[ $1 == '--init' ]]; then
  log "monitor running on $$ to initalise DS keys"
  function trap_exit() {
    log "terminating initalisation of DS keys"
    exit 1
  }
  log "monitor terminating on PID:$$"
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
files=$(find "${BIND_LOG_PATH}" -type f -not -name zone_transfers -not -name queries -printf '%p ')

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
log "MONITORING BIND LOGS ... : $files"
# fi

view_config_check
trap "trap_exit" SIGINT SIGHUP 15

LOGGER_FLAGS=${LOGGER_FLAGS} "${DIR}/dnssec-monitor.sh" --clean &

# run once and add all DS keys, regardless
LOGGER_FLAGS=${LOGGER_FLAGS} "${DIR}/dnssec-monitor.sh" --init &

monitor_pid=$!

readarray -td: views <<<"${VIEWS}"
# main monitoring/update
(
  # shellcheck disable=SC2086
  tail -n0 -f $files | stdbuf -oL grep '.*' |
    while IFS= read -r line; do
      # example
      # line='04-Jun-2022 07:12:02.164 dnssec: info: DNSKEY node.flipkick.media/ECDSAP384SHA384/29885 (KSK) is now published'
      if grep -P '.*info: DNSKEY.*\(KSK\).*published.*' <<<"$line"; then
        log ""
        key_found=0
        domain=$(awk '{print $6}' <<<"${line//\// }")
        A="00000"
        B="$(awk '{print $8}' <<<"${line//\// }")"
        key_id="$(echo "${A:0:-${#B}}$B")"

        log "KSK key_id:$key_id"

        for view in ${views[@]}; do
          key_file="/var/cache/bind/keys/${view}/K${domain}.+014+${key_id}.key"
          if [[ -f $key_file ]]; then
            key_found=1
            log "KSK Published! domain:${domain} key_id:${key_id} view:${view}"
            if [[ ! -f "${DSPROCESS_PATH}/${domain}.${view}.dsprocess" ]]; then
              touch "${DSPROCESS_PATH}/${domain}.${view}.dsprocess"
              "${DIR}/add.sh" "${domain}" "${key_id}" "${view}"
            fi
          fi
        done
        if [[ $key_found -eq 0 ]]; then
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
        log "CDS line:$line"
        key_id="$(echo "${A:0:-${#B}}$B")"

        log "CDS key_id:$key_id"
        #locate view using domain and key id
        for view in ${views[@]}; do
          key_file="/var/cache/bind/keys/${view}/K${domain}.+014+${key_id}.key"
          if [[ -f $key_file ]]; then
            key_found=1
            log "CDS Published! domain:${domain} key: ${key_id} view:${view}"
            if [[ ! -f "${DSPROCESS_PATH}/${domain}.${view}.dsprocess" ]]; then
              touch "${DSPROCESS_PATH}/${domain}.${view}.dsprocess"
              "${DIR}/update.sh" $domain $key_id $view
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
