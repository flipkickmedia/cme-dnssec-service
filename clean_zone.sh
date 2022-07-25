#!/usr/bin/env bash
service named stop
DATE_NOW=$(date +%s)
if [[ ! -d /var/cache/bind/backup/${DATE_NOW} ]]; then
  mkdir -p "/var/cache/bind/backup/${DATE_NOW}"
fi

for rx in /var/cache/bind/*.db; do
  echo processing $rx
  #strip all CDS|DS|DNSKEY|RRSIG|TYPE65534 values
  pcregrep -Mv '^\s+(CDS|DS|DNSKEY|RRSIG|TYPE65534)[\s0-9A-Za-z\n\.\(\+\/\\#]+\s\)' "$rx" >"$rx.new.0"
  #strip all NSEC values
  pcregrep -Mv '^[A-Z0-9\s]+NSEC[\sA-Z0-9\n\(]+\s\)' "$rx.new.0" >"$rx.new.1"
  pcregrep -Mv '^\s+NSEC[\sA-Z0-9]+' "$rx.new.1" >"$rx.new.2"
  #strip all TTLS apart from the TTL at the top of the zone
  readarray -td $'\n' TTLS < <(pcregrep -Mn '^\$TTL[\s\;A-Za-z0-9]+$' "$rx.new.2" | tail -n +2 | mawk -W interactive -F ':' '{print $1}')
  if [[ ${#TTLS[@]} -ne -0 ]]; then
    sed -i $(printf "%dd;" "${TTLS[@]}") $rx.new.2
  fi
  #mv $rx.new $rx
  cp "$rx.new.2" "/var/cache/bind/backup/${DATE_NOW}/$(basename $rx)"
  mv "$rx.new.2" "$rx"
done
rm -rf /var/cache/bind/*.new.*
rm -rf /var/cache/bind/*.jnl
rm -rf /var/cache/bind/*.mkeys
rm -rf /var/cache/bind/*.nzd
rm -rf /var/cache/bind/*.signed
rm -rf /var/cache/bind/*.jbk

# iterate keys and remove expired keys
current_date=$(date +%s)
for key_file in /var/cache/bind/keys/*.state; do
  echo checking key $key_file
  readarray -td. key_parts <<<"$key_file"
  key="${key_parts[0]}${key_parts[1]}"
  readarray -td$'\n' key_parts <<<"$key_file"
  ksk=$(cat $key_file | grep KSK | awk '{print $2}')
  zsk=$(cat $key_file | grep ZSK | awk '{print $2}')
  retired=$(cat $key_file | grep Retired | awk '{print $2}')
  if [[ $current_date -gt $retired ]]; then
    echo "key:$key_file is retired, removing .key .private .state"
    #rm key="${key_parts[0]}${key_parts[1]}.key"
    #rm key="${key_parts[0]}${key_parts[1]}.private"
    #rm key="${key_parts[0]}${key_parts[1]}.state"
  fi
done


#rm -rf /var/cache/bind/keys/*


#service named start
