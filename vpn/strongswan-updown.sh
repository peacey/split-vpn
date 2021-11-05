#!/bin/bash
set -o errexit

TZ="$(cat /etc/timezone)"
export TZ

if [ $# -lt 1 ]; then
	echo "ERROR: No vpn.conf file passed to $0."
	exit
fi

VPN_CONF="$1"
. "${VPN_CONF}"
VPN_CONF_DIR="$(dirname "${VPN_CONF}")"
cd "${VPN_CONF_DIR}"

# Default to a table of 101 if not given
if [ -z "${ROUTE_TABLE}" ]; then
	ROUTE_TABLE=101
fi

export VTI_IF="${DEV}"
export VPN_ENDPOINT_IPV4="${PLUTO_PEER}"
export DNS_IPV4_IP="${PLUTO_DNS4_1}"

case "${PLUTO_VERB}" in
    up-client)
		ip tunnel del "${VTI_IF}" > /dev/null 2>&1 || true
        ip tunnel add "${VTI_IF}" mode vti \
			local "${PLUTO_ME}" remote "${PLUTO_PEER}" \
            okey "${PLUTO_MARK_OUT%%/*}" ikey "${PLUTO_MARK_IN%%/*}" || true
        ip link set "${VTI_IF}" up
        ip addr add ${PLUTO_MY_SOURCEIP} dev "${VTI_IF}"
		ip route add 0.0.0.0/1 dev "${VTI_IF}" table "${ROUTE_TABLE}"
		ip route add 128.0.0.0/1 dev "${VTI_IF}" table "${ROUTE_TABLE}"
		sysctl -w "net.ipv4.conf.${VTI_IF}.disable_policy=1" > /dev/null
		sysctl -w "net.ipv4.conf.${VTI_IF}.rp_filter=0" > /dev/null
		nohup /etc/split-vpn/vpn/updown.sh "${VTI_IF}" up > "$VPN_CONF_DIR/splitvpn-up.log" 2>&1 &
        ;;
    down-client)
		nohup /etc/split-vpn/vpn/updown.sh "${VTI_IF}" down > "$VPN_CONF_DIR/splitvpn-down.log" 2>&1 &
		ip tunnel del "${VTI_IF}" || true
        ;;
esac
