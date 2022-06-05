#!/usr/bin/env bash
#
# monitor.sh
# monitor named log output for CDS published string
# run update.sh with domain
DATA_PATH="/var/cache/bind"
DSPROCESS_PATH="${DATA_PATH}/dsprocess"
BIND_LOG_PATH="/var/log/named"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
alias logger='logger ${LOGGER_FLAGS}'
# stop repeated additions via nsupdate as views are handled in the same scope as the main process
if [[ $1 == '--clean' ]]; then

  function trap_exit() {
    logger "terminating dsprocess monitor"
    exit 0
  }

  trap "trap_exit" SIGINT SIGKILL SIGSTOP 15
  alias logger='logger ${LOGGER_FLAGS}'
  logger "flags: ${LOGGER_FLAGS}"

  shopt -s extglob
  while (true); do
    for dsprocess in "${DSPROCESS_PATH}/"*.dsprocess; do
      if [ ! -f "$dsprocess" ]; then
        sleep 5
        continue
      fi
      if [[ $(date -r $dsprocess "+%s") -lt $(($(date +%s) - 60)) ]]; then
        locked_domain=$(basename $dsprocess)
        logger "removing dsprocess lock for ${locked_domain//\.dsprocess/}"
        rm $dsprocess
      fi
    done
    sleep 5
  done
fi

function trap_exit() {
  if [[ -n $monitor_pid && $(ps -p $monitor_pid) ]]; then
    logger "terminating monitor on PID:$monitor_pid"
    kill -1 $tail_pid
    wait $tail_pid
    kill -1 $monitor_pid
    wait $monitor_pid
    exit 0
  fi
}

#add interfaces for access to views
ip a a 10.0.254.2 dev eno1
ip a a 10.0.254.1 dev eno1

trap "trap_exit" SIGINT SIGKILL SIGSTOP 15

LOGGER_FLAGS=${LOGGER_FLAGS} ${DIR}/dnssec-monitor.sh --clean &
monitor_pid=$!
logger "monitor running on ${monitor_pid}"

# main monitoring/update

files=$(find ${BIND_LOG_PATH} -type f -not -name zone_transfers -not -name queries)
logger "flags: ${LOGGER_FLAGS}"
logger "monitoring $files for CDS updates"

#tail -n0 -f $files | stdbuf -oL grep '.*' |
(
  tail -n0 -f $files &
  echo $! >&3
) 3>tail_pid | stdbuf -oL grep '.*' |
  while IFS= read -r line; do
    #line='04-Jun-2022 07:12:02.164 dnssec: info: DNSKEY node.flipkick.media/ECDSAP384SHA384/29885 (KSK) is now published'
    if grep -P '.*info: DNSKEY.*\(KSK\).*published.*' <<<"$line"; then
      domain=$(awk '{print $6}' <<<"${line//\// }")
      logger "KSK Published! domain:${domain}"
      if [[ ! -f ${domain}.dsprocess ]]; then
        touch ${DSPROCESS_PATH}/${domain}.dsprocess
        ${DIR}/add.sh ${domain}
      fi
    fi

    #line='04-Jun-2022 12:00:07.686 general: info: CDS for key node.flipkick.media/ECDSAP384SHA384/16073 is now published'
    if grep -P '.*info: CDS for key.*published.*' <<<"$line"; then
      domain=$(awk '{print $8}' <<<"${line//\// }")
      logger "CDS Published! domain:${domain}"
      if [[ ! -f ${domain}.dsprocess ]]; then
        touch ${DSPROCESS_PATH}/${domain}.dsprocess
        ${DIR}/update.sh ${domain}
      fi
    fi
  done &
tail_pid=$(<pid)
wait $tail_pid
