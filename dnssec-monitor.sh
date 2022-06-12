#!/usr/bin/env bash
# dnssec-monitor.sh
# monitor named log output for CDS published string
# run update.sh with domain
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
. ${DIR}/lib.sh

readarray -td: views <<<"$VIEWS"

# stop repeated additions via nsupdate as views are handled in the same scope as the main process
if [[ $1 == '--clean' ]]; then

  function trap_exit() {
    log "terminating dsprocess monitor"
    exit 0
  }

  trap "trap_exit" SIGINT SIGKILL SIGSTOP 15

  shopt -s extglob
  while (true); do
    for dsprocess in "${DSPROCESS_PATH}/"*.dsprocess; do
      if [ ! -f "$dsprocess" ]; then
        sleep 5
        continue
      fi
      if [[ $(date -r $dsprocess "+%s") -lt $(($(date +%s) - 60)) ]]; then
        locked_domain=$(basename $dsprocess)
        log "removing dsprocess lock for ${locked_domain//\.dsprocess/}"
        rm $dsprocess
      fi
    done
    sleep 5
  done
fi

# stop repeated additions via nsupdate as views are handled in the same scope as the main process
if [[ $1 == '--monitor-external' ]]; then
  function trap_exit() {
    log "terminating external CDS check"
    exit 0
  }

  while IFS= read -r line; do
    readarray -td: ext_dns <<<"$line"
    ds="$(dig "@${NS_SERVER}" +short ${ext_dns[0]} DS)"
    if [[ "$ds" != "${ext_dns[1]}" ]]; then
      ${DIR}/update.sh ${ext_dns[0]}
    fi
  done <"$EXTERNAL_DOMAIN_LIST"

  trap "trap_exit" SIGINT SIGKILL SIGSTOP SIGHUP 15

  shopt -s extglob
  while (true); do
    if [[ -n $retry && $retry -gt $(date %+s) ]]; then
      sleep 5
      continue
    fi

    start=$(date +%s)
    retry=$(($start + $EXTERNAL_REFRESH))
    for dsprocess in "${DSPROCESS_PATH}/"*.dsprocess; do
      if [ ! -f "$dsprocess" ]; then
        sleep 5
        continue
      fi
      if [[ $(date -r $dsprocess "+%s") -lt $(($(date +%s) - 60)) ]]; then
        locked_domain=$(basename $dsprocess)
        log "removing dsprocess lock for ${locked_domain//\.dsprocess/}"
        rm $dsprocess
      fi
    done
    sleep 5
  done
fi

function trap_exit() {
  if [[ -n $monitor_pid && -n $(ps -p $monitor_pid) ]]; then
    log "monitor terminating on PID:$monitor_pid"
    kill -1 $monitor_pid
    wait $monitor_pid
  fi
  if [[ -n $tail_pid && -n $(ps -p $tail_pid) ]]; then
    kill -1 $tail_pid
    wait $tail_pid
  fi
  exit 0
}

if [[ $CME_DNSSEC_MONITOR_DEBUG -eq 1 ]]; then
  # print config
  echo "NS_SERVER .............. : ${NS_SERVER}"
  echo "DATA_PATH .............. : ${DATA_PATH}"
  echo "DSPROCESS_PATH ......... : ${DSPROCESS_PATH}"
  echo "CONF_PATH .............. : ${CONF_PATH}"
  echo "BIND_LOG_PATH .......... : ${BIND_LOG_PATH}"
  echo "KEY_PATH ............... : ${KEY_PATH}"
  echo "CME_DNSSEC_MONITOR_DEBUG : ${CME_DNSSEC_MONITOR_DEBUG}"
  echo "LOGGER_FLAGS ........... : ${LOGGER_FLAGS}"
fi

config_check

trap "trap_exit" SIGINT SIGKILL SIGSTOP 15

LOGGER_FLAGS=${LOGGER_FLAGS} ${DIR}/dnssec-monitor.sh --clean &
monitor_pid=$!
log "monitor running on ${monitor_pid} for CDS/KSK publish events"

# main monitoring/update
files=$(find ${BIND_LOG_PATH} -type f -not -name zone_transfers -not -name queries)
(
  tail -n0 -f $files | stdbuf -oL grep '.*' |
    while IFS= read -r line; do
      # example
      # line='04-Jun-2022 07:12:02.164 dnssec: info: DNSKEY node.flipkick.media/ECDSAP384SHA384/29885 (KSK) is now published'
      if grep -P '.*info: DNSKEY.*\(KSK\).*published.*' <<<"$line"; then
        domain=$(awk '{print $6}' <<<"${line//\// }")
        log "KSK Published! domain:${domain}"
        if [[ ! -f ${domain}.dsprocess ]]; then
          touch ${DSPROCESS_PATH}/${domain}.dsprocess
          ${DIR}/add.sh ${domain}
        fi
      fi

      # example
      # line='04-Jun-2022 12:00:07.686 general: info: CDS for key node.flipkick.media/ECDSAP384SHA384/16073 is now published'
      if grep -P '.*info: CDS for key.*published.*' <<<"$line"; then
        domain=$(awk '{print $8}' <<<"${line//\// }")
        log "CDS Published! domain:${domain}"
        if [[ ! -f ${domain}.dsprocess ]]; then
          touch ${DSPROCESS_PATH}/${domain}.dsprocess
          ${DIR}/update.sh ${domain}
        fi
      fi
    done
) &
tail_pid=$!
wait $tail_pid
