#!/bin/sh
# Link split-vpn directory to /etc/split-vpn
SPLIT_VPN_DIR="$(cd "$(dirname "$0")/../"; pwd -P)"
rm -f /etc/split-vpn
ln -sf "${SPLIT_VPN_DIR}" /etc/split-vpn
