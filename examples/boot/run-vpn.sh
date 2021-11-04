#!/bin/sh
rm -f /etc/split-vpn
ln -sf /mnt/data/split-vpn /etc/split-vpn
/etc/split-vpn/run-vpn.sh
