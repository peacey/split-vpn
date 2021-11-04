#!/bin/sh
cd "/etc/split-vpn/strongswan/purevpn"
. ./vpn.conf

podman rm -f strongswan-${DEV} >/dev/null 2>&1
#/etc/split-vpn/vpn/updown.sh ${DEV} pre-up
podman run -d --name strongswan-${DEV} --network host --privileged \
	-v "${PWD}:${PWD}" \
	-v "./purevpn.conf:/etc/swanctl/conf.d/purevpn.conf" \
	-v "/etc/split-vpn/vpn:/etc/split-vpn/vpn" \
	-e TZ="$(cat /etc/timezone)" \
	-v "/etc/timezone:/etc/timezone" \
	peacey/udm-strongswan
