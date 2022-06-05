#!/usr/bin/env bash

function parent_domain() {
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  echo $parent
}

DOMAIN=$1
PARENT_DOMAIN=$(parent_domain $1)
RNDC_KEYS=('external-rndc-key:SKKwYrnhqFMugles1XYflg9uhaKMmA4nQieqwflLLtM2Ox5CltvsZXd86LFbf+JRUAbYkkpImkrzh5AnX6D2zg==' 'internal-rndc-key:8gKLwTuPIEWOrwavIdALEGYZb6RX3uE1DwlMJFW7zjkRsaBfMPrlh2P2k3St4GGeo4BzncgsABXYYxXqn8SZXg==')
IFACE_INDEX=(10.0.254.2 10.0.254.1)
NS_SERVER='127.0.0.1'
TTL=60

function log() {
  /usr/bin/logger ${LOGGER_FLAGS} "$@"
}

#run updates for all views
readarray -td: views <<<"$VIEWS"
for view in ${views[@]}; do
  var="${view^^}"
  var="${var//-/_}_IFACE"
  ip_addr="${!var}"
  key_var="${var//-/_}_KEY_NAME"
  key_var="${key_var^^}"
  key_name="${!key_var}"
  key_value_name="${var^^}"
  key_value="${!key_value_name}"
  
  echo ip_addr $ip_addr
  echo key_var $key_var
  echo key_name $key_name
  echo key_value_name $key_value_name
  echo key_value $key_value

  key=${RNDC_KEYS[$i]}
  iface=${IFACE_INDEX[$i]}
  dig -b $ip_addr @${NS_SERVER} +norecurse "$DOMAIN". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "$DOMAIN" | tee "dsset-${DOMAIN}." >/dev/null
  dig -b $ip_addr @${NS_SERVER} +dnssec +noall +answer $DOMAIN DNSKEY $DOMAIN CDNSKEY $DOMAIN CDS | tee "file-${DOMAIN}" >/dev/null
  dnssec-cds -a SHA-384 -s-86400 -T ${TTL} -u -i -f file-${DOMAIN} -d . -i.orig $DOMAIN | tee ./nsup >/dev/null

  log "handling CDS publish - running nsupdate for domain:${DOMAIN} view:${view} key:${key_name}"
  if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
    cat <<EOF
#server ${NS_SERVER}
#zone ${DOMAIN}
#$(cat ./nsup)
#send
EOF
  fi

  nsupdate -y hmac-sha512:${key_name}:${key_value} < <(
    cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat ./nsup)
send
EOF
  )
  rm nsup
done
