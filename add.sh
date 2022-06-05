#!/usr/bin/env bash
# add.sh
# adds a DS key to the parent domain when there are no CDS keys present.  If this is a clean run (i.e. no keys, service named start, make a cup of tea, then run this run this on each domain from the root down.)
# e.g.
# $ service named start
# $ sleep 600
# $ add.sh node.flipkick.media ; add.sh dev.node.flipkick.media ; add subsub.dev.node.flipkick.media
# @todo error checking, this works if everything is perfect..and that's about it.
# RNDC_KEYS keys needed for nsupdate to access the correct view
# IFACE_INDEX interfaces created on a local interface, in my case, 10.0.254.1 is internal, 10.0.254.2
# is external and allow dig to bind to an address so we can provide give dig access to the correct view.
# VIEWS names of the views
# note arrays are linked indexes

function parent_domain() {
  local parent
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

DATA_PATH="${DATA_PATH:-/var/cache/bind}"
KEY_PATH="${KEY_PATH:-${DATA_PATH}/keys}"
DOMAIN=${DOMAIN:-$1}
PARENT_DOMAIN=$(parent_domain ${DOMAIN})
RNDC_KEYS=('external-rndc-key:${EXTERNAL_RNDC_KEY}' 'internal-rndc-key:${INTERNAL_RNDC_KEY}')
VIEWS=(externals-master internals-master)
IFACE_INDEX=(10.0.254.2 10.0.254.1)
NS_SERVER='127.0.0.1'
#@todo  ttl needs some work so we don't clobber the key publish/expiry times
TTL=60
alias log="/usr/bin/logger ${LOGGER_FLAGS}"

#find the id for the currently active KSK
for f in "${KEY_PATH}/K${DOMAIN}.+014+"*.state; do
  if grep -q "KSK: yes" $f; then
    if ! grep -q "Successor:" $f; then
      id=$(echo $f | grep -Po '\d+' | tail -n 1)
    fi
  fi
done
f=${f/\.state/\.key}
logger "update KSK for domain:$DOMAIN id:$id f:$f"

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
  echo $ip_addr
  echo $key_var
  echo $key_name
  echo $key_value_name
  echo $key_value
  #check to see if we have a CDS key published
  cds=$(dig -b $ip_addr @${NS_SERVER} +noall +answer $DOMAIN CDS)
  if [[ $cds == "" ]]; then
    ds=$(dnssec-dsfromkey -a SHA-384 ${KEY_PATH}/K${DOMAIN}.+014+${id}.key | awk '{print $4" "$5" "$6" "$7}')
    logger "running nsupdate for $key"
    if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
      cat <<EOF
nsupdate -y hmac-sha512:${key_name}:${key}
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
      rndc notify ${PARENT_DOMAIN} in ${VIEWS[$i]}
      rndc notify ${DOMAIN} in ${VIEWS[$i]}
    )
  fi
done
