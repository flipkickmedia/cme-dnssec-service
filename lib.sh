#!/usr/bin/env bash

function parent_domain() {
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  echo $parent
}

function log() {
  /usr/bin/logger ${LOGGER_FLAGS} "$@"
}

function config_check() {
  for view in ${views[@]}; do
    view_var="${view^^}"
    iface_var="${view_var//-/_}_IFACE"
    key_var="${view_var//-/_}_KEY_NAME"
    key_name="${!key_var}"
    key_name_var="${key_name^^}"
    key_name_var="${key_name_var//-/_}"
    iface=$(route | tail -n-1 | awk '{print $8}')
    ip_addr="${!iface_var}"
    if ! ping -c1 -w3 $ip_addr >/dev/null 2>&1; then
      # @todo get network inteface
      ip a a $ip_addr dev $iface
    fi
    key="${!key_name_var}"

    if [[ -z $key ]]; then
      echo "key NOT FOUND!..processing next view..."
      continue
    fi

    if [[ ! -f ${CONF_PATH}/rndc.${view}.conf ]]; then
      echo "${CONF_PATH}/rndc.${view}.conf not found! Exiting.."
      exit 1
    fi

    if [[ ! -f ${CONF_PATH}/rndc.${view}.key ]]; then
      echo "${CONF_PATH}/rndc.${view}.key not found! Exiting.."
      exit 1
    fi

    if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
      echo "view ................... : $view"
      echo "  ip_addr .............. : $ip_addr"
      echo "  key_name ............. : $key_name"
      echo "  key .................. : ******"
    fi
  done
}

alias log="/usr/bin/logger ${LOGGER_FLAGS}"
