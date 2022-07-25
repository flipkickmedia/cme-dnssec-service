#!/usr/bin/env bash
# add.sh
# adds a DS key to the parent domain when there are no CDS keys present.  If this is a clean run (i.e. no keys, service named start, make a cup of tea, then run this run this on each domain from the root down.)
# e.g. $ add.sh example.com
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
declare -xa VIEWS
# shellcheck disable=1091
. /etc/cme/dnssec-monitor.env
# shellcheck disable=1091
. "${DIR}/lib.sh"

DOMAIN=${DOMAIN:-$1}
KEY_ID=${KEY_ID:-$2}
VIEW=${VIEW:-$3}

PARENT_DOMAIN=$(parent_domain "${DOMAIN}")
TTL=60
view="${VIEW}"
log "adding KSK for ${DOMAIN}"
#find the id for the currently active KSK for the provided domain
for f in "${KEY_PATH}/K${DOMAIN}.+014+"*.state; do
  if grep -q "KSK: yes" "$f"; then
    if ! grep -q "Successor:" "$f"; then
      id=$(echo "$f" | grep -Po '\d+' | tail -n 1)
    fi
  fi
done
f=${f/\.state/\.key}
log "handling KSK publish - running nsupdate ${DOMAIN}"

# shellcheck disable=SC2068

view_var="${VIEW^^}"
view_var="${view_var//-/_}"
iface_var=${view_var}_IFACE
key_var=${view_var}_KEY_NAME

log "key_var: $key_var"
key_name="${!key_var}"
key_name_var="${key_name^^}"
key_name_var="${key_name_var//-/_}"
ip_addr="${!iface_var}"

if [[ ! -f "${CONF_PATH}/rndc.${VIEW}.key" ]]; then
  log "key file not found at ${CONF_PATH}/rndc.${VIEW}.key"
  exit 0
fi

if [[ ! -f "${KEY_PATH}/${VIEW}/K${DOMAIN}.+014+${KEY_ID}.key" ]]; then
  log "key file ${KEY_PATH}/${VIEW}/K${DOMAIN}.+014+${KEY_ID}.key NOT found!...processing next view..."
  exit 0
fi

log "view ................... : ${VIEW}"
log "  ip_addr .............. : ${ip_addr}"
log "  key_name ............. : ${key_name}"
log "  key_id ............... : ${KEY_ID}"
log "  key_var .............. : ${!key_var}"
log "  key .................. : ******"

#check to see if we have a CDS key published
cds=$(dig -b "$ip_addr" "@${NS_SERVER}" +noall +answer "$DOMAIN" CDS)
if [[ $cds == "" ]]; then
  ds=$(dnssec-dsfromkey -a SHA-384 "${KEY_PATH}/${VIEW}/K${DOMAIN}.+014+${KEY_ID}.key" | awk '{print $4" "$5" "$6" "$7}')
  log "DS:$ds"
  if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
    log "$(cat <<EOF
nsupdate -k "${CONF_PATH}/rndc.${VIEW}.key"
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${VIEW}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
)"
  fi

  nsupdate -l "${ip_addr}" -k "${CONF_PATH}/rndc.${VIEW}.key" < <(
    cat <<EOF
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${VIEW}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
  )

  log "rndc -k \"${CONF_PATH}/rndc.${VIEW}.key\" -c \"${CONF_PATH}/rndc.${VIEW}.conf\" notify ${PARENT_DOMAIN} in ${VIEW}"
  log "rndc -k \"${CONF_PATH}/rndc.${VIEW}.key\" -c \"${CONF_PATH}/rndc.${VIEW}.conf\" notify ${DOMAIN} in ${VIEW}"
  rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" notify ${PARENT_DOMAIN} in ${VIEW}
  rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" notify ${DOMAIN} in ${VIEW}
fi

dig -b "${ip_addr}" "@${NS_SERVER}" +norecurse "${DOMAIN}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${DOMAIN}" | tee "${DSPROCESS_PATH}/dsset-${VIEW}-${DOMAIN}." >/dev/null
dig -b "${ip_addr}" "@${NS_SERVER}" +dnssec +noall +answer "${DOMAIN}" DNSKEY "${DOMAIN}" CDNSKEY "${DOMAIN}" CDS | tee "${DSPROCESS_PATH}/file-${VIEW}-${DOMAIN}" >/dev/null
