#!/usr/bin/env bash
# add.sh
# adds a DS key to the parent domain when there are no CDS keys present.  If this is a clean run (i.e. no keys, service named start, make a cup of tea, then run this run this on each domain from the root down.)
# e.g. $ add.sh example.com

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
. ${DIR}/lib.sh

DOMAIN=${DOMAIN:-$1}
PARENT_DOMAIN=$(parent_domain ${DOMAIN})
TTL=60

#find the id for the currently active KSK for the provided domain
for f in "${KEY_PATH}/K${DOMAIN}.+014+"*.state; do
  if grep -q "KSK: yes" $f; then
    if ! grep -q "Successor:" $f; then
      id=$(echo $f | grep -Po '\d+' | tail -n 1)
    fi
  fi
done
f=${f/\.state/\.key}
log "handling KSK publish - running nsupdate ${DOMAIN}"
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

  if [[ -n ${key} ]]; then
    echo "key NOT found!...processing next view..."
    continue
  fi

  if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
    echo "view       : ${view}"
    echo "  ip_addr  : $ip_addr}"
    echo "  key_name : ${key_name}"
    echo "  key      : ******"
  fi

  #check to see if we have a CDS key published
  cds=$(dig -b $ip_addr @${NS_SERVER} +noall +answer $DOMAIN CDS)
  if [[ $cds == "" ]]; then
    ds=$(dnssec-dsfromkey -a SHA-384 ${KEY_PATH}/K${DOMAIN}.+014+${id}.key | awk '{print $4" "$5" "$6" "$7}')
    if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
      cat <<EOF
nsupdate -y hmac-sha512:${key_name}:${key}
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${view}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
    fi

    nsupdate -y hmac-sha512:${key_name}:${key} < <(
      cat <<EOF
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${view}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
    )
    rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${PARENT_DOMAIN} in ${view}
    rndc -k "${CONF_PATH}/rndc.${view}.key" -c "${CONF_PATH}/rndc.${view}.conf" notify ${DOMAIN} in ${view}
  fi
done
