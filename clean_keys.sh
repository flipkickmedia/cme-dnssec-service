#!/usr/bin/env bash
service named stop

. /etc/cme/dnssec-monitor.env

readarray -td: views <<<"${VIEWS}"
# iterate keys and remove expired keys
current_date=$(date +%Y%m%d%H%M%S)
for view in ${views[@]}; do
  for key_file in /var/cache/bind/keys/${view}/*.state; do
    ksk=$(cat $key_file | grep KSK | awk '{print $2}')
    zsk=$(cat $key_file | grep ZSK | awk '{print $2}')
    retired=$(cat $key_file | grep Retired | awk '{print $2}')
    if [[ $current_date -gt $retired ]]; then
      key=$(echo $key_file | sed s/.state//)
      echo key:$key
      rm $key.private
      rm $key.key
      rm $key.state
    fi
  done
done
