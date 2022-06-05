# cme-bind-dnssec

## Overview

Some scripts to manage DNSSEC on BIND v9.18.1 to work with DNSSEC DS/CDS keys.

## Description

To keep DNS secure https://datatracker.ietf.org/doc/html/rfc8078 provides a means for a child DNS server to be able to automatically update the parent with keys, when a CDS/CDNSKEY record changes.

These scripts monitor the bind logs for CDS and KSK publishing and updates the DS records accordingly.

## Installation

Use the CME https://cme.flipkick.media or clone this repo to somewhere safe on your DNS server. Run the install.sh to install with default values. Then edit `vim /etc/cme/cme-dnssec-monior.env` and correct the values.

```
# get scripts
sudo git clone ssh://git.flipkick.media/cme/cme-bind-dnssec /usr/local/sbin/cme-bind-dnssec
sudo cp /usr/local/sbin/cme-bind-dnssec/cme-dnssec-monitor.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/cme-dnssec-monitor.service

#create config
sudo mkdir /etc/cme
cp cme-dnssec-monitor.env /etc/cme/
chown root:root -R /etc/cme
chmod 700 /etc/cme
chmod 600 /etc/cme/cme-dnssec-monitor.env

#setup service
sudo systemctl enable bind-dnssec-monitor.service
sudo systemctl start bind-dnssec-monitor.service
sudo systemctl restart named
```

### Update

```
sudo cd /usr/local/sbin/cme-bind-dnssec
sudo git pull
sudo cp cme-dnssec-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart cme-dnssec-monitor.service
```

## Configuration

### Views

If your server has a [split horizon](https://www.google.com/search?q=split+horizon+dns) you can define the views by using the view name as part of the environment variables.

In the example config provided you can see a BIND setup with two views, externals-master and internals-master.

***Note***: You will need the associated keys and ACLs setup in BIND in order for the interface options to work correctly.

## Logging

All logs are sent to syslog.

To follow the log:

```
journalctl -f -u cme-dnssec-monitor
```

## Useful tools

### Verisign Labs

Verisign Labs have a quick checklist style validator:

[Verisign Labs DNSSEC Debugger](https://dnssec-debugger.verisignlabs.com/dev.node.flipkick.media)

### DNSViz

[DNSViz](https://dnsviz.net/d/dev.node.flipkick.media/dnssec/)

Using DNSViz you can visualise your DNS configuration for a given domain name:

![DNSViz flipkick.media](./dnsvis.png)

## CME

This forms part of the CME platform from flipkick.media

## Copyright Notice

©2022 flipkick.media Ltd - All Rights Reserved

## Licence

Please use freely and credit flipkick.media wherever you can. Donations always greatly appreciated ;)
