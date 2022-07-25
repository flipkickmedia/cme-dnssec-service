#!/usr/bin/env bash

BASEPATH=/var/cache/bind
VIEW=${1:-externals.master}

function reverse_domain() {
  local i
  local rev
  local niamod
  set -- ${1//\./ }
  for i in "$@"; do
    rev=("$i" "${rev[@]}")
  done
  niamod="${rev[*]}"
  niamod=${niamod//\ /\.}
  echo $niamod
}

created=0
shopt -s nullglob
echo "processing zones in ${BASEPATH} for view: ${VIEW}"
for fp in "/var/cache/bind/${VIEW}."*.db; do
  echo -e
  fn=$(basename $fp)
  domain=${fn//${VIEW}/}
  domain=${domain//\.db/}
  domain=$(reverse_domain $domain)
  echo "db:$fp for domain:${domain}"
  dig -b 10.0.254.2 @127.0.0.1 ${domain} DS | grep -Ev '^($|;)' > "dsset-${domain}"
  dig -b 10.0.254.2 @127.0.0.1 ${domain} DNSKEY ${domain} CDS ${domain} CDNSKEY | grep -Ev '^($|;)' > "child-${domain}"
  if ! grep -F -q -m 1 DNSKEY "dsset-${domain}"; then
    echo "dsset has no DNSKEY :("
    remove=1
  fi
  if ! grep -F -q -m 1 DS "dsset-${domain}"; then
    echo "dsset has no DS :("
    remove=1
    continue
  fi
  if [[ $remove -eq 1 ]];then
    rm -f "dsset-${domain}"
  fi
  ((created=created+1))
done
echo -e
echo "dsset: $created files created"
read
for f in dsset-*; do
  d=${f#dsset-}
  echo d:$d
  echo f:$f
  dig @127.0.0.1 +dnssec +noall +answer $d DNSKEY $d CDNSKEY $d CDS |
  dnssec-cds -i -f /dev/stdin -d $f $d
done
