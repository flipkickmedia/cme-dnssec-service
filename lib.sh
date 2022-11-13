#!/usr/bin/env bash

function parent_domain() {
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  echo -e "$parent"
  return 0
}

function log() {
  echo "$(date '+%d-%b-%Y %H:%M:%S.%3N') cme-dnssec-monitor: ${BASH_SOURCE[1]//$DIR\//} " "$@" >>/var/log/cme/dnssec-monitor
  # shellcheck disable=2086
  /usr/bin/logger ${LOGGER_FLAGS} "$@"
}

function success_icon() {
  [[ $1 -eq 0 ]] && echo -e "✅" && return "$1"
  [[ $1 -ne 0 ]] && echo -e "❗" && return "$1"
}

function view_config_check() {

  for view; do
    view_var="${view^^}"
    iface_var="${view_var//-/_}_IFACE"
    key_var="${view_var//-/_}_KEY_NAME"
    key_name="${!key_var}"
    key_name_var="${key_name^^}"
    key_name_var="${key_name_var//-/_}"
    iface=$(route | tail -n-1 | awk '{print $8}')
    ip_addr="${!iface_var}"
    if ! ping -c1 -w3 "$ip_addr" >/dev/null 2>&1; then
      # @todo get network inteface
      ip a a "$ip_addr" dev "$iface"
    fi
    key="${!key_name_var}"

    if [[ -z $key ]]; then
      log "key NOT FOUND!..processing next view..."
      continue
    fi

    if [[ ! -f "${CONF_PATH}/rndc.${view}.conf" ]]; then
      log "${CONF_PATH}/rndc.${view}.conf not found! Exiting.."
      exit 1
    fi

    if [[ ! -f "${CONF_PATH}/rndc.${view}.key" ]]; then
      log "${CONF_PATH}/rndc.${view}.key not found! Exiting.."
      exit 1
    fi

    if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
      log "view ................... : $view"
      log "  ip_addr .............. : $ip_addr"
      log "  key_name ............. : $key_name"
      log "  key .................. : ******"
    fi
  done
}

if [[ -d ${DSPROCESS_PATH} ]]; then
  mkdir -p "${DSPROCESS_PATH}"
  chown root:root "${DSPROCESS_PATH}"
  chmod 777 "${DSPROCESS_PATH}"
fi

if [[ ! -f "${DSPROCESS_PATH}/${EXTERNAL_DOMAINS_LIST}" ]]; then
  cp "${DATA_PATH}/${EXTERNAL_DOMAINS_LIST}" "${DSPROCESS_PATH}/${EXTERNAL_DOMAINS_LIST}"
fi

# shellcheck disable=SC2139
alias log="/usr/bin/logger ${LOGGER_FLAGS}"
