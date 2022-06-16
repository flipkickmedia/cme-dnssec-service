#!/usr/bin/env bash
# run cme-external-cds-monitor.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ ${CME_DNSSEC_MONITOR_DEBUG=notloaded} == "notloaded" ]]; then
  . ${DIR}/dnssec-monitor.env
fi
. ${DIR}/lib.sh

# create some common time offsets
function create_time_offsets() {
  # $1 is the current epoch
  DATE_10M=$(($1 + 600))
  DATE_60M=$(($1 + 3600))
  DATE_1D=$(($1 + 86400))
}

log "monitor running on $$ for external CDS updates"

# external domains monitoring - check every 30mins for DS record updates
while (true); do
  while IFS= read -r domain; do
    log "external CDS check:$domain"
    touch "${DSPROCESS_PATH}/external-cds-$domain"
    dig +short $domain NS | sort | tee "${DSPROCESS_PATH}/external-cds-$domain" |
      while IFS= read -r server; do
        touch "${DSPROCESS_PATH}/external-cds-$domain-NS-A"
        dig @"${NS_SERVER}" +short "$server" PTR | sort | tee "${DSPROCESS_PATH}/external-cds-$domain-NS-A" >/dev/null
        echo" running: tail -n0 "${DSPROCESS_PATH}/external-cds-$domain-NS-A""
        a_record=$(tail -n0 "${DSPROCESS_PATH}/external-cds-$domain-NS-A")
        echo test:$a_record
      done

  done <"${DSPROCESS_PATH}/$EXTERNAL_DOMAINS_LIST"
  sleep $((600))
done
