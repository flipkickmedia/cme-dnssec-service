# cme-bind-dnssec

## Overview

Some scripts to manage DNSSEC on bind to work with CDS keys.

## Description

To keep DNS secure https://datatracker.ietf.org/doc/html/rfc8078 provides a means for a child DNS server to be able to automatically update the parent with keys, when a CDS/CDNSKEY record changes.

These scripts monitor the bind logs for CDS and KSK publishing and updates the DS records accordingly.

To use, extract the files to somewhere safe on your DNS server, `/usr/local/sbin` is a good place, and run `monitor.sh` script before starting named.

## CME

This forms part of the CME system from flipkick.media

## Copyright Notice

©2022 flipkic.kmedia Ltd - All Rights Reserved

## Licence

Please use freely and credit flipkick.media wherever you can. Donations always greatly appreciated ;)
