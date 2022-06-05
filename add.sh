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

#run updates for all views
readarray -td: views <<<"$VIEWS"
for view in ${views[@]}; do
  var="${view^^}"
  var="${var//-/_}_IFACE"
  ip_addr="${!var}"
  key_var="${var//-/_}_KEY_NAME"
  key_name="${!var}"
  key_value_name="${var^^}"
  key_value="${!key_value_name}"

  echo ip_addr $ip_addr
  echo key_var $key_var
  echo key_name $key_name
  echo key_value_name $key_value_name
  echo key_value $key_value
  #check to see if we have a CDS key published
  cds=$(dig -b $ip_addr @${NS_SERVER} +noall +answer $DOMAIN CDS)
  if [[ $cds == "" ]]; then
    ds=$(dnssec-dsfromkey -a SHA-384 ${KEY_PATH}/K${DOMAIN}.+014+${id}.key | awk '{print $4" "$5" "$6" "$7}')
    log "handling KSK publish - running nsupdate for view:${view} key:${key_name}"
    if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
      cat <<EOF
nsupdate -y hmac-sha512:${key_name}:${key_value}
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${VIEWS[$i]}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
    fi

    nsupdate -y hmac-sha512:${key_name}:${key_value} < <(
      cat <<EOF
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${VIEWS[$i]}
add ${DOMAIN}. ${TTL} DS $ds
send
EOF
    )
    rndc -k ./rndc.${view}.key -c ./rndc.${view}.conf notify ${PARENT_DOMAIN} in ${VIEWS[$i]}
    rndc -k ./rndc.${view}.key -c ./rndc.${view}.conf notify ${DOMAIN} in ${VIEWS[$i]}
  fi
done
