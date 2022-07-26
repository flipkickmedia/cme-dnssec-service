#!/usr/bin/env bash
# update.sh
# updates a DS key on the parent domain based on the CDS key being published.
# e.g. $ update.sh example.com
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=1091
. /etc/cme/dnssec-monitor.env
# shellcheck disable=1091
. "${DIR}/lib.sh"
log "update DEBUG pre param set 1:$1 2:$2 3:$3"
log "update DEBUG pre param set DOMAIN:$DOMAIN KEY_ID:$KEY_ID VIEW:$VIEW"
DOMAIN=${DOMAIN:-$1}
KEY_ID=${KEY_ID:-$2}
VIEW=${VIEW:-$3}
log "update DEBUG post param set DOMAIN:$DOMAIN KEY_ID:$KEY_ID VIEW:$VIEW"

PARENT_DOMAIN=$(parent_domain "${DOMAIN}")
TTL=60

log "handling CDS publish - running nsupdate for domain:${DOMAIN} view:$view"

# shellcheck disable=SC2068
view_var="${VIEW^^}"
view_var="${view_var//-/_}"
iface_var=${view_var}_IFACE
key_var=${view_var}_KEY_NAME

key_name="${!key_var}"
key_name_var="${key_name^^}"
key_name_var="${key_name_var//-/_}"
ip_addr="${!iface_var}"

log "view ................... : ${view}"
log "  ip_addr .............. : ${ip_addr}"
log "  key_name ............. : ${key_name}"
log "  key .................. : ******"
log "  TTL .................. : $TTL"

if [[ ! -f "${CONF_PATH}/rndc.${view}.key" ]]; then
  log "key file not found at ${CONF_PATH}/rndc.${view}.key"
  exit 0
fi

if [[ ! -d ${DSPROCESS_PATH} ]]; then
  mkdir "${DSPROCESS_PATH}"
  chmod 770
  touch "${DSPROCESS_PATH}/dsset-${view}-${DOMAIN}."
  touch "${DSPROCESS_PATH}/file-${view}-${DOMAIN}"
  touch "${DSPROCESS_PATH}/nsup"
fi
log "removing old nsup"
rm "${DSPROCESS_PATH}/nsup.${view}.${domain}"
dig -b "${ip_addr}" "@${NS_SERVER}" +norecurse "${DOMAIN}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${DOMAIN}" | tee "${DSPROCESS_PATH}/dsset-${view}-${DOMAIN}." >/dev/null
dig -b "${ip_addr}" "@${NS_SERVER}" +dnssec +noall +answer "${DOMAIN}" DNSKEY "${DOMAIN}" CDNSKEY "${DOMAIN}" CDS | tee "${DSPROCESS_PATH}/file-${view}-${DOMAIN}" >/dev/null
log "$(dnssec-cds -a SHA-384 -s-86400 -T "${TTL}" -u -i -f "${DSPROCESS_PATH}/file-${view}-${DOMAIN}" -d "${DSPROCESS_PATH}/." -i"${DSPROCESS_PATH}/.orig" "${DOMAIN}" | tee "${DSPROCESS_PATH}/nsup.${view}.${DOMAIN}" >/dev/null)"
log "$(cat ${DSPROCESS_PATH}/nsup.${view}.${DOMAIN})"

log "$(
  cat <<EOF
nsupdate -k "${CONF_PATH}/rndc.${view}.key" < <(
server ${NS_SERVER}
zone ${DOMAIN}
$(cat ${DSPROCESS_PATH}/nsup.${view}.${DOMAIN})
send
)
EOF
)"

nsupdate -l "${ip_addr}" -k "${CONF_PATH}/rndc.${view}.key" < <(
  cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat ${DSPROCESS_PATH}/nsup)
send
EOF
)
log "notifying ${PARENT_DOMAIN} in ${view}"
rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${PARENT_DOMAIN} in ${view}
log "notifying ${DOMAIN} in ${view}"
rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${DOMAIN} in ${view}
