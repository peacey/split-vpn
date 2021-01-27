#!/bin/sh
# This script adds the iptables rules for the VPN. It is usually called by updown.sh script.

# Exit if an error is encountered
set -e 

# ./add-vpn-iptables-rules.sh [up/down/force-down] [tun_dev]

CHAINS="mangle:PREROUTING mangle:POSTROUTING mangle:FORWARD nat:PREROUTING nat:POSTROUTING filter:INPUT filter:FORWARD"

# Create the iptables chains
create_chains() {
	for entry in ${CHAINS}; do
		table=$(echo ${entry} | cut -d':' -f1)
		chain=$(echo ${entry} | cut -d':' -f2)
		iptables -t ${table} -N ${PREFIX}${chain} &> /dev/null || true
		ip6tables -t ${table} -N ${PREFIX}${chain} &> /dev/null || true
		add_rule both ${table} "${chain} -j ${PREFIX}${chain}" noprefix
	done
}

# Delete the iptables chains
delete_chains() {
	for entry in ${CHAINS}; do
		table=$(echo ${entry} | cut -d':' -f1)
		chain=$(echo ${entry} | cut -d':' -f2)
		iptables -t ${table} -D ${chain} -j ${PREFIX}${chain} &> /dev/null || true
		ip6tables -t ${table} -D ${chain} -j ${PREFIX}${chain} &> /dev/null || true
		iptables -t ${table} -F ${PREFIX}${chain} &> /dev/null || true
		ip6tables -t ${table} -F ${PREFIX}${chain} &> /dev/null || true
		iptables -t ${table} -X ${PREFIX}${chain} &> /dev/null || true
		ip6tables -t ${table} -X ${PREFIX}${chain} &> /dev/null || true
	done
}

# add_rule IPV4/IPV6/both TABLE "RULE" (prefix=noprefix)
# Add an iptables rule. 
add_rule() {
	if [[ "$4" = "noprefix" ]]; then
		prefix=""
	else
		prefix=${PREFIX}
	fi
	if [[ "$1" = "IPV4" ]]; then
		iptables -t $2 -C ${prefix}$3 &> /dev/null || iptables -t $2 -A ${prefix}$3
	elif [[ "$1" = "IPV6" ]]; then
		ip6tables -t $2 -C ${prefix}$3 &> /dev/null || ip6tables -t $2 -A ${prefix}$3
	else
		iptables -t $2 -C ${prefix}$3 &> /dev/null || iptables -t $2 -A ${prefix}$3
		ip6tables -t $2 -C ${prefix}$3 &> /dev/null || ip6tables -t $2 -A ${prefix}$3
	fi
}

# Get the first IPv4 DNS server provided by the VPN server's DHCP options if option is set.
# These options are found in foreign_option_i. 
get_dns() {
	if [[ "${DNS_IPV4_IP}" != "DHCP" ]]; then
		return
	fi
	# Only check a maximum of 1000 options. Usually only get 1 or 2. 
	for i in $(seq 1 1000); do
		foreign_option_i=$(eval echo \$foreign_option_$i)
		if [ -x "${foreign_option_i}" ]; then
			break
		fi
		dns=$(echo "${foreign_option_i}" | sed -E s/".*dhcp-option DNS ([0-9\.]+).*"/"\1"/g)
		if [ -x "${dns}" ]; then
			continue
		fi
		DNS_IPV4_IP="${dns}"
		DNS_IPV4_PORT=53
		break
	done
}

# Add iptables rules
add_iptables_rules() {
	# Force traffic through VPN for each forced interface
	for interface in ${FORCED_SOURCE_INTERFACE}; do
		add_rule both mangle "PREROUTING -i ${interface} -j MARK --set-xmark ${MARK}"
	done

	# Force traffic through VPN for each forced IPv4 or IPv6 source
	for ip in ${FORCED_SOURCE_IPV4}; do
		add_rule IPV4 mangle "PREROUTING -s ${ip} -j MARK --set-xmark ${MARK}"
	done
	for ip in ${FORCED_SOURCE_IPV6}; do
		add_rule IPV6 mangle "PREROUTING -s ${ip} -j MARK --set-xmark ${MARK}"
	done

	# Force traffic through VPN for each forced mac source
	for mac in ${FORCED_SOURCE_MAC}; do
		add_rule both mangle "PREROUTING -m mac --mac-source ${mac} -j MARK --set-xmark ${MARK}"
	done

	# Exempt sources from VPN
	for ip in ${EXEMPT_SOURCE_IPV4}; do
		add_rule IPV4 mangle "PREROUTING -s ${ip} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
	done
	for ip in ${EXEMPT_SOURCE_IPV6}; do
		add_rule IPV6 mangle "PREROUTING -s ${ip} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
	done
	for mac in ${EXEMPT_SOURCE_MAC}; do
		add_rule both mangle "PREROUTING -m mac --mac-source ${mac} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
	done

	# Exempt source IP:PORT for IPv4 and IPv6
	for entry in ${EXEMPT_SOURCE_IPV4_PORT}; do
		proto=$(echo "$entry" | cut -d'-' -f1)
		source_ip=$(echo "$entry" | cut -d'-' -f2)
		sports=$(echo "$entry" | cut -d'-' -f3)
		for sport in $(echo "${sports}" | sed s/","/" "/g); do
			if [[ "$proto" = "both" ]]; then
				add_rule IPV4 mangle "PREROUTING -p tcp -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
				add_rule IPV4 mangle "PREROUTING -p udp -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
			else
				add_rule IPV4 mangle "PREROUTING -p ${proto} -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
			fi
		done
	done
	for entry in ${EXEMPT_SOURCE_IPV6_PORT}; do
		proto=$(echo "$entry" | cut -d'-' -f1)
		source_ip=$(echo "$entry" | cut -d'-' -f2)
		sports=$(echo "$entry" | cut -d'-' -f3)
		for sport in $(echo "${sports}" | sed s/","/" "/g); do
			if [[ "$proto" = "both" ]]; then
				add_rule IPV6 mangle "PREROUTING -p tcp -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
				add_rule IPV6 mangle "PREROUTING -p udp -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
			else
				add_rule IPV6 mangle "PREROUTING -p ${proto} -s ${source_ip} --sport ${sport} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
			fi
		done
	done

	# Exempt IPv4/IPv6 destinations from VPN
	for dest in ${EXEMPT_DESTINATIONS_IPV4}; do
		add_rule IPV4 mangle "PREROUTING ! -i ${dev} -d ${dest} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
	done
	for dest in ${EXEMPT_DESTINATIONS_IPV6}; do
		add_rule IPV6 mangle "PREROUTING ! -i ${dev} -d ${dest} -m mark --mark ${MARK} -j MARK --set-xmark 0x0"
	done

	# Masquerade output traffic from VPN interface (dynamic SNAT)
	add_rule both nat "POSTROUTING -o ${dev} -j MASQUERADE"

	# Force DNS through VPN for VPN traffic or REJECT VPN DNS traffic.
	get_dns
	for proto in udp tcp; do
		if [[ "${DNS_IPV4_IP}" = "REJECT" ]]; then
			add_rule IPV4 filter "INPUT -m mark --mark ${MARK} -p ${proto} --dport 53 -j REJECT"
			add_rule IPV4 filter "FORWARD -m mark --mark ${MARK} -p ${proto} --dport 53 -j REJECT"
		elif [ ! -x ${DNS_IPV4_IP} ]; then
			add_rule IPV4 nat "PREROUTING -m mark --mark ${MARK} -p ${proto} ! -s ${DNS_IPV4_IP} ! -d ${DNS_IPV4_IP} --dport 53 -j DNAT --to ${DNS_IPV4_IP}:${DNS_IPV4_PORT:-53}"
			if [ ! -x ${DNS_IPV4_INTERFACE} ]; then
				add_rule IPV4 mangle "FORWARD -m mark --mark ${MARK} -d ${DNS_IPV4_IP} -p ${proto} --dport ${DNS_IPV4_PORT:-53} -j MARK --set-xmark 0x0"
				ip route replace ${DNS_IPV4_IP} dev ${DNS_IPV4_INTERFACE} table ${ROUTE_TABLE}
			fi
		fi
		if [[ "${DNS_IPV6_IP}" = "REJECT" ]]; then
			add_rule IPV6 filter "INPUT -m mark --mark ${MARK} -p ${proto} --dport 53 -j REJECT"
			add_rule IPV6 filter "FORWARD -m mark --mark ${MARK} -p ${proto} --dport 53 -j REJECT"
		elif [ ! -x ${DNS_IPV6_IP} ]; then
			add_rule IPV6 nat "PREROUTING -m mark --mark ${MARK} -p ${proto} ! -s ${DNS_IPV6_IP} ! -d ${DNS_IPV6_IP} --dport 53 -j DNAT --to [${DNS_IPV6_IP}]:${DNS_IPV6_PORT:-53}"
			if [ ! -x ${DNS_IPV6_INTERFACE} ]; then
				add_rule IPV6 mangle "FORWARD -m mark --mark ${MARK} -d ${DNS_IPV6_IP} -p ${proto} --dport ${DNS_IPV6_PORT:-53} -j MARK --set-xmark 0x0"
				ip -6 route replace ${DNS_IPV6_IP} dev ${DNS_IPV6_INTERFACE} table ${ROUTE_TABLE}
			fi
		fi
	done

	# Forward ports on VPN side for IPv4 or IPv6 entries
	for entry in ${PORT_FORWARDS_IPV4}; do
		proto=$(echo "$entry" | cut -d'-' -f1)
		dport_vpn=$(echo "$entry" | cut -d'-' -f2)
		dest_ip=$(echo "$entry" | cut -d'-' -f3)
		dport=$(echo "$entry" | cut -d'-' -f4)
		if [[ "$proto" = "both" ]]; then
			add_rule IPV4 nat "PREROUTING -i ${dev} -p tcp --dport ${dport_vpn} -j DNAT --to-destination ${dest_ip}:${dport}"
			add_rule IPV4 nat "PREROUTING -i ${dev} -p udp --dport ${dport_vpn} -j DNAT --to-destination ${dest_ip}:${dport}"
		else
			add_rule IPV4 nat "PREROUTING -i ${dev} -p ${proto} --dport ${dport_vpn} -j DNAT --to-destination ${dest_ip}:${dport}"
		fi
	done
	for entry in ${PORT_FORWARDS_IPV6}; do
		proto=$(echo "$entry" | cut -d'-' -f1)
		dport_vpn=$(echo "$entry" | cut -d'-' -f2)
		dest_ip=$(echo "$entry" | cut -d'-' -f3)
		dport=$(echo "$entry" | cut -d'-' -f4)
		if [[ "$proto" = "both" ]]; then
			add_rule IPV6 nat "PREROUTING -i ${dev} -p tcp --dport ${dport_vpn} -j DNAT --to-destination [${dest_ip}]:${dport}"
			add_rule IPV6 nat "PREROUTING -i ${dev} -p udp --dport ${dport_vpn} -j DNAT --to-destination [${dest_ip}]:${dport}"
		else
			add_rule IPV6 nat "PREROUTING -i ${dev} -p ${proto} --dport ${dport_vpn} -j DNAT --to-destination [${dest_ip}]:${dport}"
		fi
	done
}

# Add the iptables kill switch
add_killswitch() {
	# Create the custom chain
	iptables -t filter -N ${PREFIX}KILLSWITCH &> /dev/null || true
	ip6tables -t filter -N ${PREFIX}KILLSWITCH &> /dev/null || true
	add_rule both filter "OUTPUT -j ${PREFIX}KILLSWITCH" noprefix
	add_rule both filter "FORWARD -j ${PREFIX}KILLSWITCH" noprefix

	# Reject all VPN traffic (marked) that doesn't go out of the VPN interface
	add_rule both filter "KILLSWITCH -m mark --mark ${MARK} ! -o ${dev} -j REJECT"
}

# Delete the iptables kill switch
delete_killswitch() {
	iptables -t filter -D OUTPUT -j ${PREFIX}KILLSWITCH &> /dev/null || true
	ip6tables -t filter -D OUTPUT -j ${PREFIX}KILLSWITCH &> /dev/null || true
	iptables -t filter -D FORWARD -j ${PREFIX}KILLSWITCH &> /dev/null || true
	ip6tables -t filter -D FORWARD -j ${PREFIX}KILLSWITCH &> /dev/null || true
	iptables -t filter -F ${PREFIX}KILLSWITCH &> /dev/null || true
	ip6tables -t filter -F ${PREFIX}KILLSWITCH &> /dev/null || true
	iptables -t filter -X ${PREFIX}KILLSWITCH &> /dev/null || true
	ip6tables -t filter -X ${PREFIX}KILLSWITCH &> /dev/null || true
}

# If configuration variables are not present, source the config file from the PWD.
if [ -x ${MARK} ]; then
	source ./vpn.conf
fi

# Default to tun0 if no device name was passed to this script
if [ -x "$2" ]; then
	dev=tun0
else
	dev="$2"
fi

# When this script is called from updown.sh, first argument is either up or down.
if [[ "$1" = "up" ]]; then
	if [ ${KILLSWITCH} = 1 ]; then
		add_killswitch
	fi
	create_chains
	add_iptables_rules
elif [[ "$1" = "down" ]]; then
	if [ ${REMOVE_KILLSWITCH_ON_EXIT} = 1 ]; then
		delete_chains
		delete_killswitch
	fi
elif [[ "$1" = "force-down" ]]; then
	delete_chains
	delete_killswitch
fi
