# cme-bind-dnssec

## Overview

Some scripts to manage DNSSEC on BIND v9.18.1 to work with DNSSEC DS/CDS keys.

## Description

To keep DNS secure https://datatracker.ietf.org/doc/html/rfc8078 provides a means for a child DNS server to be able to automatically update the parent with keys, when a CDS/CDNSKEY record changes.

These scripts monitor the bind logs for CDS and KSK publishing and updates the DS records accordingly.

## Installation
To use, extract the files to somewhere safe on your DNS server, `/usr/local/sbin` is a good place

```
sudo git clone ssh://git.flipkick.media/cme/cme-bind-dnssec /usr/local/sbin/cme-bind-dnssec
sudo cp /usr/local/sbin/cme-bind-dnssec/bind-dnssec-monitor.service /etc/systemd/system/
sudo systemctl enable bind-dnssec-monitor.service
sudo systemctl start bind-dnssec-monitor.service
sudo systemctl restart named
```

## Update
```
cd /usr/local/sbin/cme-bind-dnssec
sudo git pull
cp *.service /etc/systemd/system/
systemctl daemon-reload
systemctl restart cme-dnssec-monitor.service
``

## Info

USing DNSVis you can visualise your DNS configuration for a given domain name.

https://dnsviz.net/d/dev.node.flipkick.media/dnssec/

![DNSVIS flipkick.media](./dnsvis.png)

## CME

This forms part of the CME system from flipkick.media

## Copyright Notice

©2022 flipkick.media Ltd - All Rights Reserved

## Licence

Please use freely and credit flipkick.media wherever you can. Donations always greatly appreciated ;)
