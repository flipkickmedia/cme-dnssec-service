#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [[ ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} == "notloaded" || ${CME_DNSSEC_MONITOR_DEBUG:-notloaded} -eq 0 ]]; then
  # shellcheck disable=SC1091
  . "/etc/cme/dnssec-monitor.env"
fi
# shellcheck disable=SC1091
. "${DIR}/lib.sh"

declare ip_addr=$1
declare ns_server=$2
declare domain=$3
declare ttl=$4
declare view=$5
declare dsprocess_path=${DSPROCESS_PATH:-$}
declare domain_key=/etc/bind/rndc.${view}.key
declare domain_conf=/etc/bind/rndc.${view}.conf

# declare ip_addr=10.0.254.2
# declare ns_server=10.0.254.2
# declare parent_domain=entitywind.io
# declare domain=node.entitywind.io
# declare view=externals-master
# declare ttl=60
# declare domain_key=/etc/bind/rndc.externals-master.key
# declare domain_conf=/etc/bind/rndc.externals-master.conf

declare dsprocess_path=/tmp/cme

declare -a domain_array
declare -a domain_array_rev

declare parent_domain
declare parent_domain_rev

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

readarray -td '.' domain_array < <(printf "%s" "$domain")
readarray -td '' domain_array_rev < <(
  ((${#domain_array[@]})) && printf '%s\0' "${domain_array[@]}" | tac -s ''
)

parent_domain=$(join_by '.' "${domain_array[@]:1:${#domain_array[@]}}")

echo "ip_addr:${ip_addr}"
echo "ns_server:${ns_server}"
echo "parent_domain:${parent_domain}"
echo "domain:${domain}"
echo "view:${view}"
echo "ttl:${ttl}"
echo "domain_key:${domain_key}"
echo "domain_conf:${domain_conf}"
echo -e

echo "syncing"
rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" sync -clean

echo "flushing ${parent_domain}"
rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" flush ${view}

echo "thawing ${parent_domain}"
rndc -c ${domain_conf} -k ${domain_key} thaw "${parent_domain}" IN "${view}"

echo "thawing ${domain}"
rndc -c ${domain_conf} -k ${domain_key} thaw "${domain}" IN "${view}"

# get the records
readarray -td$'\n' ds_records < <(dig -b "${ip_addr}" "@${ns_server}" +norecurse "${domain}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${domain}")
readarray -td$'\n' cds_records < <(dig -b "${ip_addr}" "@${ns_server}" +short +norecurse "${domain}". CDS)

echo "ds_records:"
echo "${ds_records[*]}"
echo -e
echo "cds_records:"
echo "${cds_records[*]}"
echo -e

echo "thawing ${parent_domain}"
rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" sync -clean
rndc -c ${domain_conf} -k ${domain_key} thaw "${parent_domain}" IN "${view}"
rndc -c ${domain_conf} -k ${domain_key} thaw "${domain}" IN "${view}"

echo -e "clean up previous DS records in ${parent_domain}"
nsupdate -k ${domain_key} <<EOFT
server ${ns_server}
zone ${domain}.
update del ${domain}. DS
send
quit
EOFT
echo " result: $?"

echo "syncing"
rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" sync -clean

echo -e "clean up previous CDS records in ${parent_domain}"
nsupdate -k ${domain_key} <<EOFT
server ${ns_server}
zone ${domain}.
update del ${domain}. CDS
send
quit
EOFT
echo " result: $?"

echo "syncing"
rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" sync -clean

# if we have no CDS records, we need to add the DS records to the parent domain
if [[ ${#cds_records} -ne ${#ds_records} ]]; then
  declare record
  for ds_record in "${ds_records[@]}"; do
    record="$(echo -e $ds_record | awk '{print $4" "$5" "$6" "$7}')"
    declare -a record_parts
    # shellcheck disable=SC2206
    record_parts+=(${record[@]})
    # @todo check to see if the state file for the key has been superceeded, if so remove the cds key in question
    echo -e "adding CDS key domain:$domain parent_domain:$parent_domain key_id:${record_parts[0]}"
    cat <<EOF
zone ${domain}.
update add ${domain}. ${ttl} CDS $record
EOF

    nsupdate -k /etc/bind/rndc.externals-master.key <<EOFT
server ${ns_server}
zone ${domain}.
update add ${domain}. ${ttl} CDS $record
send
quit
EOFT
    echo " result: $?"

    echo -e "adding DS key domain:$domain parent_domain:$parent_domain key_id:${record_parts[0]}"
    cat <<EOF
zone ${parent_domain}.
update add ${domain}. ${ttl} DS $record
EOF

    nsupdate -k /etc/bind/rndc.externals-master.key <<EOFT
server ${ns_server}
zone ${parent_domain}.
update add ${domain}. ${ttl} DS $record
send
quit
EOFT
    echo " result: $?"

    echo "syncing"
    rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" sync -clean

    echo "flushing ${parent_domain}"
    rndc -c ${domain_conf} -k ${domain_key} -s "${ns_server}" flush ${view}

    echo "notifying ${domain}"
    rndc -c ${domain_conf} -k ${domain_key} notify "${domain}" IN "${view}"

    echo "notifying ${parent_domain}"
    rndc -c ${domain_conf} -k ${domain_key} notify "${parent_domain}" IN "${view}"
  done
fi
