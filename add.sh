#!/usr/bin/env bash 
function parent_domain() {
  local parent
  set -- ${1//\./ }
  shift
  set -- "$@"
  parent="$*"
  parent=${parent//\ /\.}
  echo $parent
}

DOMAIN=$1
PARENT_DOMAIN=$(parent_domain ${DOMAIN})
RNDC_KEYS=('external-rndc-key:SKKwYrnhqFMugles1XYflg9uhaKMmA4nQieqwflLLtM2Ox5CltvsZXd86LFbf+JRUAbYkkpImkrzh5AnX6D2zg==' 'internal-rndc-key:8gKLwTuPIEWOrwavIdALEGYZb6RX3uE1DwlMJFW7zjkRsaBfMPrlh2P2k3St4GGeo4BzncgsABXYYxXqn8SZXg==')
IFACE_INDEX=(10.0.254.2 10.0.254.1)
VIEWS=(externals-master internals-master)
NS_SERVER='127.0.0.1'

#find the id for the currently active KSK
for f in "/var/cache/bind/keys/K${DOMAIN}"*.state;do
  if grep -q "KSK: yes" $f;then
    if ! grep -q "Successor:" $f;then
      id=$(echo $f | grep -Po '\d+' | tail -n 1)
    fi
  fi
done
f=${f/\.state/\.key}
echo domain:$DOMAIN id:$id f:$f

for i in ${!RNDC_KEYS[@]}; do
  key=${RNDC_KEYS[$i]};
  iface=${IFACE_INDEX[$i]}

  #check to see if we have a CDS key published
  cds=$(dig -b $iface @127.0.0.1 +noall +answer $DOMAIN CDS)
  if [[ $cds == "" ]];then
    ds=$(dnssec-dsfromkey -a SHA-384 /var/cache/bind/keys/K${DOMAIN}.+014+${id}.key | awk '{print $4" "$5" "$6" "$7}')

 #   echo running nsupdate for $key
    cat << EOF
add ${DOMAIN}. 600 DS $ds
EOF

    nsupdate -y hmac-sha512:${key} < <(cat <<EOF
server ${NS_SERVER}
zone ${PARENT_DOMAIN}. in ${VIEWS[$i]}
add ${DOMAIN}. 600 DS $ds
send
EOF
rndc sign ${PARENT_DOMAIN} in ${VIEWS[$i]}
rndc sign ${DOMAIN} in ${VIEWS[$i]}
rndc notify ${PARENT_DOMAIN} in ${VIEWS[$i]}
rndc notify ${DOMAIN} in ${VIEWS[$i]}
)

  fi
done
echo -e
