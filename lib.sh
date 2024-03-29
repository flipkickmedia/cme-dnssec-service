#!/usr/bin/env bash
#set +e #otherwise the script will exit on error

echo loading lib...

rndc_cmd=$(which rndc)
nsupdate_cmd=$(which rndc)

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

function parent_domain() {
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  sleep 1
  echo -e "$parent"
  return 0
}

function log() {
  echo "$(date '+%d-%b-%Y %H:%M:%S.%3N') cme-dnssec-monitor:${BASH_SOURCE[1]//$DIR\//} " "$@" >>${LOG_FILE:-"/var/log/cme/dnssec-monitor.log"} 2>&1
  # shellcheck disable=2086
  /usr/bin/logger ${LOGGER_FLAGS} "${BASH_SOURCE[1]//$DIR\//} $@"
}

function success_icon() {
  [[ $1 -eq 0 ]] && echo -e "✅" && return "$1"
  [[ $1 -ne 0 ]] && echo -e "❌" && return "$1"
}

function render_params() {
  log "domain              : ${domain}"
  log "domain_parent       : ${domain_parent}"
  log "view                : ${view}"
  log "ip_addr             : ${ip_addr}"
  log "ns_server           : ${ns_server}"
  log "ttl                 : ${ttl}"
  log "key_id              : ${key_id}"
  log "key_path            : ${key_path}"
  log "dsprocess_path      : ${dsprocess_path}"
  log "domain_key          : ${domain_key}"
  log "domain_conf         : ${domain_conf}"
}

# @function config_init
# initalises the variables needed for a typical dnssec operation using nsupadte and rndc
function config_init() {
  declare view_var="${view^^}"
  declare iface_var="${view_var//-/_}_IFACE"
  declare ns_server_var="${view_var//-/_}_NS_SERVER"
  declare key_var="${view_var//-/_}_KEY_NAME"
  key_name="${!key_var}"
  declare key_name_var="${key_name^^}"
  declare key_name_var="${key_name_var//-/_}"
  ksk_key_path="${key_path}/${view}/K${domain}.+014+${key_id}.key"
  ksk_state_path="${key_path}/${view}/K${domain}.+014+${key_id}.state"
  domain_key="/etc/bind/rndc.${view}.key"
  domain_conf="/etc/bind/rndc.${view}.conf"
  domain_parent="$(parent_domain $domain)"
  depth="$(tld_depth $domain)"
  parent_depth="$(tld_depth $domain_parent)"

  log "view ............: ${view}"
  log "depth ...........: ${depth}"
  log "parent_depth ....: ${parent_depth}"
  log "domain ..........: ${domain}"
  log "domain_parent ...: ${domain_parent}"

  #log "view_var ........: ${view_var}"
  #log "iface_var .......: ${iface_var}"

  key_path=${KEY_PATH:-${DATA_PATH}/keys}
  dsprocess_path=${DSPROCESS_PATH:-/tmp/cme/dsprocess}

  ip_addr="${!iface_var}"
  ns_server=${!ns_server_var}
  iface="${!iface_var}"
  iface_name=$(route | tail -n-1 | awk '{print $8}')
  key="${!key_name_var}"
  key_path=${KEY_PATH}
  #log "key_var .........: ${key_var}"
  #log "key_name_var ....: ${key_name_var}"
  log "key_name ........: ${key_name}"
  log "iface_name.......: ${iface_name}"
  log "iface............: ${iface}"
  log "ip_addr .........: ${ip_addr}"
  log "ns_server........: ${ns_server}"
  log "key_path.........: ${key_path}"

  if ! ping -c1 -w3 "$ip_addr" >/dev/null 2>&1; then
    log "pinging interface for nsserver $ip_addr $iface_name"
    ip a a "$ip_addr" dev "$iface_name"
    log "added ip address to $ip_addr / $iface_name"
  fi

  if [[ ! -f "${domain_conf}" ]]; then
    log "${domain_conf} not found! Exiting.."
    exit 1
  fi

  if [[ ! -f "${domain_key}" ]]; then
    log "${domain_key} not found! Exiting.."
    exit 1
  fi

  if [[ ! -f "${dsprocess_path}/${EXTERNAL_DOMAINS_LIST}" ]]; then
    log "copying ${DATA_PATH}/${EXTERNAL_DOMAINS_LIST} to ${dsprocess_path}/${EXTERNAL_DOMAINS_LIST}"
    cp "${DATA_PATH}/${EXTERNAL_DOMAINS_LIST}" "${dsprocess_path}/${EXTERNAL_DOMAINS_LIST}"
  fi

  if [[ ! -d "${dsprocess_path}/${view}" ]]; then
    mkdir "${dsprocess_path}/${view}"
  fi

  chown root:root "${dsprocess_path}/${view}"
  chmod 770 "${dsprocess_path}/${view}"

  # find the id for the currently active KSK for the provided domain
  find_valid_ksk_file

  log "found_ksk_key ....: ${found_key}"
  [[ ${#key_id} -lt 5 ]] && key_id=$(printf "%05d" "${key_id}")
  log "key_id ...........: ${key_id}"
  log "ksk_file .........: ${ksk_file}"
  log "key_path .........: ${key_path}"

  if [[ ! -f "${domain_key}" ]]; then
    log "rndc key file not found at ${domain_key}! Aborting"
    exit 2
  fi

  if [[ ! -f "${ksk_file}.key" ]]; then
    log "ksk key file not found at ${ksk_file}.key! Aborting"
    exit 2
  fi

  if [[ ! -d "${key_path}" ]]; then
    log "${key_path} NOT found! Aborting."
    exit 2
  fi

  if [[ ! -d "${dsprocess_path}/${view}" ]]; then
    mkdir "${dsprocess_path}/${view}"
  fi

  chown root:root "${dsprocess_path}"
  chmod 777 "${dsprocess_path}"
  chmod 777 "${dsprocess_path}/${view}"
}

function find_valid_ksk_file() {
  found_key=false
  local _ksk_file
  for _ksk_file in ${key_path}/${view}/K${domain}.+014+*.state; do
    if grep -q "KSK: yes" "$_ksk_file"; then
      if ! grep -q "Successor:" "$_ksk_file"; then
        key_id=$(echo "$_ksk_file" | grep -Po '\d+' | tail -n 1)
        ksk_file="${_ksk_file//\.state/}"
        found_key=true
      fi
    fi
  done
}

function find_view_from_ksk_id() {
  declare -i sleep_time=1
  declare -i max_sleep=20
  declare -i curr_sleep=0
  while [[ $key_found == "false" ]]; do
    if [[ $max_sleep -le $curr_sleep ]]; then
      log "...cant wait any longer for key: ${key_file}"
      break
    fi

    for view in "${views[@]}"; do
      find_valid_ksk_file
      if [[ $found_key == "true" ]]; then
        break 2
      fi
    done
    curr_sleep=$((curr_sleep + sleep_time))
    log "current_sleep:$curr_sleep"
    sleep $sleep_time
  done
}

function containsElement() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function refresh_domain() {
  rndc_out="$(rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean 2>&1)"
  log "$(success_icon $?)...syncing ............: all views"\n"${rndc_out}"

  rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" flush "${view}"
  log "$(success_icon $?)...flushing view ......: ${view}"

  rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" thaw "${domain}" IN "${view}"
  log "$(success_icon $?)...thawing ............: ${domain} in ${view}"
}

function notify_domain() {
  rndc -c ${domain_conf} -k ${domain_key} notify "${domain}" IN "${view}"
  log "$(success_icon $?)...notifying ${domain}"

  rndc -c ${domain_conf} -k ${domain_key} notify "${domain_parent}" IN "${view}"
  log "$(success_icon $?)...notifying ${domain_parent}"
}

function prepare_domain() {
  rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" flush "${view}"
  log "$(success_icon $?)...flushing view ......: ${view}"

  # rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" freeze "${domain_parent}" IN "${view}"
  # log "$(success_icon $?)...freezing ...........: ${domain_parent} in ${view}"

  # rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" freeze "${domain}" IN "${view}"
  # log "$(success_icon $?)...freezing ...........: ${domain} in ${view}"

  rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean
  log "$(success_icon $?)...syncing ............: all views"

  rndc -c "${domain_conf}" -k "${domain_key}" thaw "${domain_parent}" IN "${view}"
  log "$(success_icon $?)...thawing ............: ${domain_parent} in ${view}"

  rndc -c "${domain_conf}" -k "${domain_key}" thaw "${domain}" IN "${view}"
  log "$(success_icon $?)...thawing ............: ${domain} in ${view})"
}

# check the component parts of a domain in reverse to see if they can be matched against a list of tlds
# so we can get a depth to iterate to when trying to find the zone name and database file
function tld_depth() {
  local domain=$1
  local domain_array=()
  local domain_array_rev=()
  local count=0
  local match=0
  local depth
  local e

  domain_var=${domain//\./_}
  domain_var=${domain_var^^}
  declare -xn depth_var="DOMAIN_${domain_var}_DEPTH"

  # @todo fix this cache
  # if [[ -n ${!depth_var} ]]; then
  #   echo "$(date) DEBUG using tld_depth cache" >>"$log" 2>&1
  #   echo -e $depth_var
  #   exit 0
  # fi

  if [[ -z $TLD_DOMAINS ]]; then
    declare -xa TLD_DOMAINS
    mkdir -p /tmp/cme
    if [[ $(stat -c'%n %Z' /tmp/cme/.tld-domain-list.txt | awk '{print $2}') -lt $(date +%s)-86399 ]] || [[ ! -f /tmp/cme/.tld-domain-list.txt ]]; then
      wget -O /tmp/cme/.tld-domain-list.txt https://data.iana.org/TLD/tlds-alpha-by-domain.txt
    fi
    mapfile -t TLD_DOMAINS </tmp/cme/.tld-domain-list.txt
  else
    log "existing TLD domains valid: /tmp/cme/.tld-domain-list.txt"
  fi

  readarray -td. domain_array < <(printf '%s' "$domain")
  readarray -td '' domain_array_rev < <(
    ((${#domain_array[@]})) && printf '%s\0' "${domain_array[@]}" | tac -s ''
  )

  count=${#domain_array[@]}
  for e in "${domain_array_rev[@]}"; do
    containsElement "${e^^}" "${TLD_DOMAINS[@]}"
    if [[ $? -eq 0 ]]; then
      match=$((match + 1))
    fi
  done
  depth=$((count - match))
  depth_var=$depth

  if [[ $depth_var ]]; then
    echo -e $depth_var
    return 0
  fi

  echo -e $depth
  return 0
}
