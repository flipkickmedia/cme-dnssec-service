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

log "monitor running on ${monitor_pid} for external CDS updates"

# external domains monitoring - check every 30mins for DS record updates
while (true); do
  while IFS= read -r domain; do
    log "external CDS check:$domain"
    touch "${DSPROCESS_PATH}/external-cds-$domain"
    dig +short $domain NS | sort | tee ${DSPROCESS_PATH}/external-cds-$domain |
      while IFS= read -r ns_server; do
        dig +short $ns_server NS | sort | tee ${DSPROCESS_PATH}/external-cds-$domain-NS-A >/dev/null
        ns_server=$(tail -n 1 "${DSPROCESS_PATH}/external-cds-$domain-NS-A")
        echo $ns_server
      done

  done <"$EXTERNAL_DOMAINS_LIST"
  sleep $((600))
done
