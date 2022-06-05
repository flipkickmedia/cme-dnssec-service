#!/usr/bin/env bash
# installer for cme-dnssec-monitor.sh

# get scripts
sudo git clone ssh://git.flipkick.media/cme/cme-bind-dnssec /usr/local/sbin/cme-bind-dnssec
sudo cp /usr/local/sbin/cme-bind-dnssec/cme-dnssec-monitor.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/cme-dnssec-monitor.service

#create config
if [[ ! -d /etc/cme && ! -f /etc/cme/cme-dnsset-monitor.env ]]; then
  sudo mkdir /etc/cme
  cp cme-dnssec-monitor.env /etc/cme/
fi
chown root:root -R /etc/cme
chmod 700 /etc/cme
chmod 600 /etc/cme/cme-dnssec-monitor.env

#setup service
sudo systemctl enable bind-dnssec-monitor.service
sudo systemctl start bind-dnssec-monitor.service
sudo systemctl restart named
