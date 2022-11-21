declare ip_addr=10.0.254.2
declare ns_server=10.0.254.2
declare domain_parent=node.flipkick.media
declare domain=prod.node.flipkick.media
declare view=externals-master
declare ttl=60
declare domain_key=/etc/bind/rndc.externals-master.key
declare domain_conf=/etc/bind/rndc.externals-master.conf
declare dsprocess_path="/tmp/cme/dsprocess"
declare CONF_PATH=/etc/bind

#reset ; /usr/local/sbin/cme-dnssec-monitor/clean ${ip_addr} ${ns_server} ${domain} ${ttl} ${view}
#/usr/local/sbin/cme-dnssec-monitor/init ${ip_addr} ${ns_server} ${domain} ${ttl} ${view}


if [[ ! -f "${dsprocess_path}/${view}/dsset-${domain}." ]]; then
log "creating dnsec-cds DS dsset file"
  dig -b "${ip_addr}" "@${ns_server}" +norecurse "${domain}". DNSKEY | dnssec-dsfromkey -a SHA-384 -f - "${domain}" | tee "${dsprocess_path}/${view}/dsset-${domain}." >/dev/null
fi
log "creating dnsec-cds CDS file"
dig -b "${ip_addr}" "@${ns_server}" +dnssec +noall +answer "${domain}" DNSKEY "${domain}" CDNSKEY "${domain}" CDS | tee "${dsprocess_path}/${view}/file-${domain}" >/dev/null

log "creating dnsec-cds nsup"
log "$(dnssec-cds -a SHA-384 -s-86400 -T "${ttl}" -u -i -f "${dsprocess_path}/${view}/file-${domain}" -d "${dsprocess_path}/${view}" -i"orig" "${domain}" | tee "${dsprocess_path}/${view}/nsup.${domain}" >/dev/null)"

log "content dnsec-cds DS file"
echo ${dsprocess_path}/${view}/dsset-${domain}.
cat ${dsprocess_path}/${view}/dsset-${domain}.
log "content dnsec-cds CDS file"
echo ${dsprocess_path}/${view}/file-${domain}
cat ${dsprocess_path}/${view}/file-${domain}
log "content dnsec-cds nsup file"
echo ${dsprocess_path}/${view}/nsup.${domain}
cat ${dsprocess_path}/${view}/nsup.${domain}
