#!/usr/bin/env bash
# update.sh
# updates a DS key on the parent domain based on the CDS key being published.
# e.g. $ update.sh example.com
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=1091
. /etc/cme/dnssec-monitor.env
# shellcheck disable=1091
. "${DIR}/lib.sh"
DOMAIN=${DOMAIN:-$1}
KEY_ID=${KEY_ID:-$2}
VIEW=${VIEW:-$3}
PARENT_DOMAIN=$(parent_domain "${DOMAIN}")
TTL=60

# shellcheck disable=SC2068
view_var="${VIEW^^}"
view_var="${view_var//-/_}"
iface_var=${view_var}_IFACE
key_var=${view_var}_KEY_NAME
key_name="${!key_var}"
key_name_var="${key_name^^}"
key_name_var="${key_name_var//-/_}"
ip_addr="${!iface_var}"
key_file="${CONF_PATH}/rndc.${VIEW}.key"

log "handling CDS publish"
log "view ................... : ${VIEW}"
log "domain ................. : ${DOMAIN}"
log "key_id ................. : ${KEY_ID}"
log "key_var ................ : ${!key_var}"
log "ip_addr ................ : ${ip_addr}"
log "key_name ............... : ${key_name}"
log "key_file ................: ${key_file}"
log "TTL .................... : $TTL"

if [[ ! -f "${CONF_PATH}/rndc.${VIEW}.key" ]]; then
  log "rndc key file not found at ${CONF_PATH}/rndc.${VIEW}.key! Aborting"
  exit 0
fi

if [[ ! -f "${KEY_PATH}/${VIEW}/K${DOMAIN}.+014+${KEY_ID}.key" ]]; then
  log "key file ${KEY_PATH}/${VIEW}/K${DOMAIN}.+014+${KEY_ID}.key NOT found! Aborting."
  exit 0
fi

if [[ ! -d "${DSPROCESS_PATH}/${VIEW}" ]]; then
  mkdir "${DSPROCESS_PATH}/${VIEW}"
  chmod 770
  touch "${DSPROCESS_PATH}/${VIEW}/dsset-${VIEW}-${DOMAIN}."
  touch "${DSPROCESS_PATH}/${VIEW}/file-${VIEW}-${DOMAIN}"
  touch "${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN}"
fi

log "removing old nsup"
rm "${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN}"
mkdir -p "${DSPROCESS_PATH}/${VIEW}"
dig -b "${ip_addr}" "@${NS_SERVER}" +norecurse "${DOMAIN}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${DOMAIN}" | tee "${DSPROCESS_PATH}/${VIEW}/dsset-${DOMAIN}." >/dev/null
dig -b "${ip_addr}" "@${NS_SERVER}" +dnssec +noall +answer "${DOMAIN}" DNSKEY "${DOMAIN}" CDNSKEY "${DOMAIN}" CDS | tee "${DSPROCESS_PATH}/${VIEW}/file-${DOMAIN}" >/dev/null
log "$(dnssec-cds -a SHA-384 -s-86400 -T "${TTL}" -u -i -f "${DSPROCESS_PATH}/${VIEW}/file-${DOMAIN}" -d "${DSPROCESS_PATH}/${VIEW}" -i".orig" "${DOMAIN}" | tee "${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN}" >/dev/null)"
log "$(cat ${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN})"

log "$(
  cat <<EOF
nsupdate -k "${CONF_PATH}/rndc.${VIEW}.key" < <(
server ${NS_SERVER}
zone ${PARENT_DOMAIN}
$(cat ${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN})
send
)
EOF
)"

nsupdate -l "${ip_addr}" -k "${CONF_PATH}/rndc.${VIEW}.key" < <(
  cat <<EOF
server ${NS_SERVER}
zone ${PARENT_DOMAIN}
$(cat ${DSPROCESS_PATH}/${VIEW}/nsup.${DOMAIN})
send
EOF
)

log "syncing ${PARENT_DOMAIN} in ${VIEW}"
rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" sync -clean ${PARENT_DOMAIN} in ${VIEW}
log "syncing ${DOMAIN} in ${VIEW}"
rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" sync -clean ${DOMAIN} in ${VIEW}

log "notifying ${PARENT_DOMAIN} in ${VIEW}"
rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" notify ${PARENT_DOMAIN} in ${VIEW}
log "notifying ${DOMAIN} in ${VIEW}"
rndc -k "${CONF_PATH}/rndc.${VIEW}.key" -c "${CONF_PATH}/rndc.${VIEW}.conf" notify ${DOMAIN} in ${VIEW}
