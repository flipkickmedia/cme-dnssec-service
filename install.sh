#!/usr/bin/env bash
# installer for cme-dnssec-monitor / external-cds-monitor

# get scripts
if [[ ! -d /usr/local/sbin/cme-bind-dnssec ]]; then
  sudo git clone ssh://git.flipkick.media/cme/cme-bind-dnssec /usr/local/sbin/cme-bind-dnssec
else
  (
    cd /usr/local/sbin/cme-bind-dnssec
    sudo git reset --hard
    sudo git pull
  )
fi

sudo cp /usr/local/sbin/cme-bind-dnssec/cme-dnssec-monitor.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/cme-dnssec-monitor.service

sudo cp /usr/local/sbin/cme-bind-dnssec/cme-external-cds-monitor.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/cme-external-cds-monitor.service

#create config
if [[ ! -d /etc/cme && ! -f /etc/cme/dnsset-monitor.env ]]; then
  sudo mkdir /etc/cme
  cp dnssec-monitor.env /etc/cme/
fi
chown root:root -R /etc/cme
chmod 700 /etc/cme
chmod 600 /etc/cme/dnssec-monitor.env

#setup service
sudo systemctl enable cme-dnssec-monitor.service
sudo systemctl enable cme-external-cds-monitor.service
sudo systemctl start cme-dnssec-monitor.service
sudo systemctl start cme-external-cds-monitor.service
sudo systemctl restart named
exit 0
