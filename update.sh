#!/usr/bin/env bash
# update.sh
# updates a DS key on the parent domain based on the CDS key being published.
# e.g. $ update.sh example.com

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
. ${DIR}/lib.sh

DOMAIN=$1
PARENT_DOMAIN=$(parent_domain $1)
TTL=60

log "handling CDS publish - running nsupdate for domain:${DOMAIN}"
#run updates for all views
readarray -td: views <<<"$VIEWS"
for view in ${views[@]}; do
  view_var="${view^^}"
  iface_var="${view_var//-/_}_IFACE"
  key_var="${view_var//-/_}_KEY_NAME"
  key_name="${!key_var}"
  key_name_var="${key_name^^}"
  key_name_var="${key_name_var//-/_}"
  ip_addr="${!iface_var}"
  key="${!key_name_var}"

  if [[ -z $key ]]; then
    echo "key NOT FOUND!..processing next view..."
    continue
  fi

  if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
    echo "view ................... : ${view}"
    echo "  ip_addr .............. : $ip_addr}"
    echo "  key_name ............. : ${key_name}"
    echo "  key .................. : ******"
  fi

  dig -b ${ip_addr} "@${NS_SERVER}" +norecurse "${DOMAIN}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${DOMAIN}" | tee "/tmp/cme-dnssec-monitor/dsset-${DOMAIN}." >/dev/null
  dig -b ${ip_addr} "@${NS_SERVER}" +dnssec +noall +answer "${DOMAIN}" DNSKEY "${DOMAIN}" CDNSKEY "${DOMAIN}" CDS | tee "/tmp/cme-dnssec-monitor/file-${DOMAIN}" >/dev/null
  dnssec-cds -a SHA-384 -s-86400 -T "${TTL}" -u -i -f "/tmp/cme-dnssec-monitor/file-${DOMAIN}" -d . -i.orig "${DOMAIN}" | tee "/tmp/cme-dnssec-monitor/nsup" >/dev/null

  if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
    cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat /tmp/cme-dnssec-monitor/nsup)
send
EOF
  fi

  nsupdate -y hmac-sha512:${key_name}:${key} < <(
    cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat /tmp/cme-dnssec-monitor/nsup)
send
EOF
  )
  rm /tmp/cme-dnssec-monitor/nsup
  rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${PARENT_DOMAIN} in ${view}
  rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${DOMAIN} in ${view}
done
