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

declare domain_key="/etc/bind/rndc.${view}.key"
declare domain_conf="/etc/bind/rndc.${view}.conf"
# shellcheck disable=SC2086,2155
declare domain_parent="$(parent_domain $domain)"

log "ip_addr:${ip_addr}"
log "ns_server:${ns_server}"
log "domain_parent:${domain_parent}"
log "domain:${domain}"
log "view:${view}"
log "ttl:${ttl}"
log "domain_key:${domain_key}"
log "domain_conf:${domain_conf}"

log "flushing ${view}"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" flush "${view}"

log "syncing"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean

log "thawing ${domain_parent}"
rndc -c "${domain_conf}" -k "${domain_key}" thaw "${domain_parent}" IN "${view}"

log "thawing ${domain}"
rndc -c "${domain_conf}" -k "${domain_key}" thaw "${domain}" IN "${view}"

# get the records
readarray -td$'\n' ds_dnskey_records < <(dig -b "${ip_addr}" "@${ns_server}" +norecurse "${domain}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${domain}")
readarray -td$'\n' cds_records < <(dig -b "${ip_addr}" "@${ns_server}" +short +norecurse "${domain}". CDS)
readarray -td$'\n' ds_records < <(dig -b "${ip_addr}" "@${ns_server}" +short +norecurse "${domain}". DS)

log ""
log "ds_dnskey_records:"
log "${ds_dnskey_records[*]}"
log ""
log "cds_records:"
log "${cds_records[*]}"
log ""
log "ds_records:"
log "${ds_records[*]}"
log ""

nsupdate -k "${domain_key}" <<EOFT
server ${ns_server}
zone ${domain_parent}.
update del ${domain}. DS
send
quit
EOFT
log "clean up previous DS records in ${domain_parent}: result: $?"

echo "syncing"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean


nsupdate -k "${domain_key}" <<EOFT
server ${ns_server}
zone ${domain_parent}.
update del ${domain}. CDS
send
quit
EOFT
echo -e "clean up previous CDS records in ${domain_parent}: result: $?"


nsupdate -k "${domain_key}" <<EOFT
server ${ns_server}
zone ${domain_parent}.
update del ${domain}. DS
send
quit
EOFT
echo -e "clean up previous DS records in ${domain_parent}: result: $?"

echo "syncing"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean

echo -e "clean up previous CDS records in ${domain}"
nsupdate -k "${domain_key}" <<EOFT
server ${ns_server}
zone ${domain_parent}.
update del ${domain}. CDS
send
quit
EOFT
echo " result: $?"

echo "syncing"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" sync -clean

echo "flushing ${view}"
rndc -c "${domain_conf}" -k "${domain_key}" -s "${ns_server}" flush "${view}"

# get the records
readarray -td$'\n' ds_dnskey_records < <(dig -b "${ip_addr}" "@${ns_server}" +norecurse "${domain}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${domain}")
readarray -td$'\n' cds_records < <(dig -b "${ip_addr}" "@${ns_server}" +short +norecurse "${domain}". CDS)
readarray -td$'\n' ds_records < <(dig -b "${ip_addr}" "@${ns_server}" +short +norecurse "${domain}". CDS)

log "ds_dnskey_records:"
log "${ds_dnskey_records[*]}"
log "cds_records:"
log "${cds_records[*]}"
log "ds_records:"
log "${ds_records[*]}"
