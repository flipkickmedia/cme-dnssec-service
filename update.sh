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

#@todo touch -t $(date +%Y%M%d%H%M) "dsset-${z}."
#dig @127.0.0.1 +norecurse "$d". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "$d" | tee "dsset-${d}." >/dev/null
#dnssec-dsfromkey -a SHA-384 /var/cache/bind/keys/K${d}.+014+${id}.key | tee "dsset-${d}."

echo -e

for i in ${!RNDC_KEYS[@]}; do
  key=${RNDC_KEYS[$i]}
  iface=${IFACE_INDEX[$i]}
  dig -b $iface @${NS_SERVER} +norecurse "$DOMAIN". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "$DOMAIN" | tee "dsset-${DOMAIN}." >/dev/null
  dig -b $iface @${NS_SERVER} +dnssec +noall +answer $DOMAIN DNSKEY $DOMAIN CDNSKEY $DOMAIN CDS | tee "file-${DOMAIN}" >/dev/null
  dnssec-cds -a SHA-384 -s-86400 -T ${TTL} -u -i -f file-${DOMAIN} -d . -i.orig $DOMAIN | tee ./nsup >/dev/null

  logger "updating CDS running nsupdate for $key"
  cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat ./nsup)
send
EOF

  nsupdate -y hmac-sha512:${key} < <(
    cat <<EOF
server ${NS_SERVER}
zone ${DOMAIN}
$(cat ./nsup)
send
EOF
  )
  rm nsup
done
