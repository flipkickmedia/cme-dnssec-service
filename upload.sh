#!/usr/bin/env bash
DIR="$(cd "$(dirname "$(readlink -f "$0")")" >/dev/null 2>&1 && pwd)"
cd $DIR || exit
function getcpid() {
    cpids=$(pgrep -P $1|xargs)
#    echo "cpids=$cpids"
    for cpid in $cpids;
    do
        echo "$cpid"
        getcpid $cpid
    done
}
ppid=$$
while inotifywait -e modify ./*; do
	rsync --verbose --links --delete --recursive --times --atimes --executability --perms --hard-links --safe-links --force "./" "root@192.168.88.254:/usr/local/sbin/cme-dnssec-monitor"
done
