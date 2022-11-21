#!/usr/bin/env bash
# run external-cds-monitor.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ ${CME_DNSSEC_EXTERNAL_MONITOR_DEBUG=notloaded} == "notloaded" ]]; then
  # shellcheck disable=SC1091
  . "/etc/cme/dnssec-monitor.env"
fi
# shellcheck disable=SC1091
. "${DIR}/lib.sh"

# create some common time offsets
function create_time_offsets() {
  # $1 is the current epoch
  export DATE_10M=$(($1 + 600))
  export DATE_60M=$(($1 + 3600))
  export DATE_1D=$(($1 + 86400))
}

log "monitor running on $$ for external CDS updates"

# external domains monitoring - check every 30mins for DS record updates
while (true); do
  if [[ ! -d ${DSPROCESS_PATH} ]]; then
    mkdir -p "${DSPROCESS_PATH}"
  fi
  while IFS= read -r domain; do
    log "external CDS check:$domain"
    touch "${DSPROCESS_PATH}/external-cds-${domain}"
    dig +short "$domain" NS | sort | tee "${DSPROCESS_PATH}/external-cds-${domain}" |
      while IFS= read -r server; do
        touch "${DSPROCESS_PATH}/external-cds-$domain-NS-A"
        if [[ $CME_DNSSEC_EXTERNAL_MONITOR_DEBUG -eq 1 ]]; then
          echo "running: dig @${server} +short ${domain} CDS"
        fi
        dig "@{$server}" +short "${domain}" CDS | tee -a "${DSPROCESS_PATH}/external-cds-$domain-CDS" >/dev/null
        if [[ $CME_DNSSEC_EXTERNAL_MONITOR_DEBUG -eq 1 ]]; then
          cat "${DSPROCESS_PATH}/external-cds-$domain-CDS"
          echo "running: tail -n0 \"${DSPROCESS_PATH}/external-cds-$domain-CDS\""
        fi
        if [[ $(stat --printf="%s" "${DSPROCESS_PATH}/external-cds-$domain-CDS") -gt 0 ]]; then
        # shellcheck disable=SC2034
          a_record=$(tail -n1 "${DSPROCESS_PATH}/external-cds-$domain-NS-A")
        else
          echo empty file
        fi
        echo "test:$server"
      done

  done <"${DSPROCESS_PATH}/$EXTERNAL_DOMAINS_LIST"
  sleep $((60))
done
