#!/usr/bin/env bash
# update.sh
# adds a DS key to the parent domain when there are no CDS keys present.  If this is a clean run (i.e. no keys, service named start, make a cup of tea, then run this run this on each domain from the root down.)
# e.g. $ update.sh example.com
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
. ${DIR}/lib.sh

DOMAIN=$1
PARENT_DOMAIN=$(parent_domain $1)
TTL=60

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
  rndc -k ./rndc.${view}.key -c ./rndc.${view}.conf notify ${PARENT_DOMAIN} in ${VIEWS[$i]}
  rndc -k ./rndc.${view}.key -c ./rndc.${view}.conf notify ${DOMAIN} in ${VIEWS[$i]}
done
