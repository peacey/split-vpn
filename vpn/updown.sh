#!/bin/sh
# This script adds/removes the VPN routes and calls the iptables vpn script.
# This script is called by openvpn's up and down hooks.

# Set -e shell option to exit if any error is encountered
set -e 

### Functions ###

# Kill the rule watcher (previously running up/down script for the tunnel device).
kill_rule_watcher() {
	for p in $(pgrep -f "sh.*$(basename "$0") $tun "); do
		if [ $p != $$ ]; then
			kill -9 $p
		fi
	done
	# Only delete the rules if not in pre-up or up hook
	if [ "$state" != "pre-up" -a "$state" != "up" ]; then
		ip rule del $ip_rule &> /dev/null || true
		ip -6 rule del $ip_rule &> /dev/null || true
	fi
}

# Run the rule watcher which will be used to re-add the policy-based ip rules
# if removed. Rule watcher keeps this script running in the background.
run_rule_watcher() {
	kill_rule_watcher
	(while :; do
		ip rule show fwmark ${MARK} | grep ${MARK} &> /dev/null || 
			(ip rule add $ip_rule && echo "[$(date)] Readded IPv4 rule.")
		ip -6 rule show fwmark ${MARK} | grep ${MARK} &> /dev/null || 
			(ip -6 rule add $ip_rule && echo "[$(date)] Readded IPv6 rule.")
		if [ "${REMOVE_STARTUP_BLACKHOLES}" = 1 ]; then
			for route in ${startup_blackholes}; do
				ip route del blackhole "$route" &> /dev/null &&
					echo "[$(date)] Removed blackhole ${route}."
			done
		fi
		if [ -z "${GATEWAY_TABLE}" -o "${GATEWAY_TABLE}" = "auto" ]; then
			add_gateway_route
		fi
 		sleep ${WATCHER_TIMER}
	done) > rule-watcher.log &
}

# Get the gateway from the UDM/P custom WAN table..
# 201 = Ethernet table, 202 = SFP+ table, 203 = U-LTE.
get_gateway() {
	tables=""
	if [ -z "${GATEWAY_TABLE}" -o "${GATEWAY_TABLE}" = "auto"  ]; then
		tables=$(ip rule | sed -En s/".*from all lookup (20[123]).*"/"\1"/p | tail -n1)
	elif [ -n "$GATEWAY_TABLE" ]; then
		tables="$GATEWAY_TABLE"
	fi
	if [ -z "${tables}" ]; then
		tables="201 202 203"
	fi
	for table in ${tables}; do
		gateway_ipv4_old="${gateway_ipv4}"
		gateway_ipv6_old="${gateway_ipv6}"
		gateway_ipv4=$(ip route show table ${table} 0.0.0.0/0 | sed -En s/".*default ((via [^ ]+ )?dev [^ ]+).*"/"\1"/p | tail -n1)
		gateway_ipv6=$(ip -6 route show table ${table} ::/0 | sed -En s/".*default ((via [^ ]+ )?dev [^ ]+).*"/"\1"/p | tail -n1)
		if [ -n "${gateway_ipv4}" ]; then
			current_table="${table}"
			break
		fi
	done
}

# netmask_to_cidr [mask]
# Convert the netmask @mask to CIDR notation.
netmask_to_cidr() {
    num_bits=0
    for octet in $(echo $1 | sed 's/\./ /g'); do 
         num_binary_bits=$(echo "ibase=10; obase=2; ${octet}"| bc | sed 's/0//g') 
         num_bits=$(expr $num_bits + ${#num_binary_bits})
    done
    echo "${num_bits}"
}

# Add the VPN routes to the custom table for OpenVPN provider.
# OpneVPN will pass route_* and dev environment variables to this script.
add_vpn_routes() {
	# Flush route table first
	delete_vpn_routes

	# Add default route to VPN
	ip route replace 0.0.0.0/1 via ${route_vpn_gateway} dev ${dev} table ${ROUTE_TABLE}
	ip route replace 128.0.0.0/1 via ${route_vpn_gateway} dev ${dev} table ${ROUTE_TABLE}
	ip -6 route replace ::/1 dev ${dev} table ${ROUTE_TABLE}
	ip -6 route replace 8000::/1 dev ${dev} table ${ROUTE_TABLE}

	# Add VPN routes from environment variables supplied by OpenVPN
	# Only check a maximum of 1000 routes. Usually only get < 10.
	for i in $(seq 1 1000); do
		route_network_i=$(eval echo \$route_network_$i)
		route_gateway_i=$(eval echo \$route_gateway_$i)
		route_netmask_i=$(eval echo \$route_netmask_$i)
		if [ -z "${route_network_i}" ]; then
			break
		fi
		cidr=$(netmask_to_cidr $route_netmask_i)
		if [ -n "${route_gateway_i}" ]; then
			ip route replace ${route_network_i}/${cidr} via ${route_gateway_i} dev ${dev} table ${ROUTE_TABLE}
		else
			ip route replace ${route_network_i}/${cidr} dev ${dev} table ${ROUTE_TABLE}
		fi
	done
	for i in $(seq 1 1000); do
		route_ipv6_network_i=$(eval echo \$route_ipv6_network_$i)
		route_ipv6_gateway_i=$(eval echo \$route_ipv6_gateway_$i)
		if [ -z "${route_ipv6_network_i}" ]; then
			break
		fi
		if [ -n "${route_ipv6_gateway_i}" ]; then
			ip -6 route replace ${route_ipv6_network_i} via ${route_ipv6_gateway_i} dev ${dev} table ${ROUTE_TABLE}
		else
			ip -6 route replace ${route_ipv6_network_i} dev ${dev} table ${ROUTE_TABLE}
		fi
	done
}

# Add the VPN endpoint -> WAN gateway route.
add_gateway_route() {
	get_gateway
	if [ -n "${trusted_ip}" -a "${VPN_PROVIDER}" = "openvpn" ]; then
		VPN_ENDPOINT_IPV4="${trusted_ip}"
	fi
	if [ -n "${trusted_ip6}" -a "${VPN_PROVIDER}" = "openvpn" ]; then
		VPN_ENDPOINT_IPV6="${trusted_ip6}"
	fi
	if [ -n "${VPN_ENDPOINT_IPV4}" -a -n "${gateway_ipv4}" ]; then
		if [ "${gateway_ipv4}" != "${gateway_ipv4_old}" ]; then
			echo "$(date +'%a %b %d %H:%M:%S %Y') split-vpn: Using IPv4 gateway from table ${current_table}: ${gateway_ipv4}."
			ip route replace ${VPN_ENDPOINT_IPV4} ${gateway_ipv4} table ${ROUTE_TABLE} || true
		fi
	fi
	if [ -n "${VPN_ENDPOINT_IPV6}" -a -n "${gateway_ipv6}" ]; then
		if [ "${gateway_ipv6}" != "${gateway_ipv6_old}" ]; then
			echo "$(date +'%a %b %d %H:%M:%S %Y') split-vpn: Using IPv6 gateway from table ${current_table}: ${gateway_ipv6}."
			ip -6 route replace ${VPN_ENDPOINT_IPV6} ${gateway_ipv6} table ${ROUTE_TABLE} || true
		fi
	fi
}

# Add blackhole routes so if VPN routes are deleted everything is rejected
# Helps to prevent leaks during VPN restarts.
add_blackhole_routes() {
	if [ "${DISABLE_BLACKHOLE}" = "1" ]; then
		return
	fi
	ip route replace blackhole default table ${ROUTE_TABLE}
	ip -6 route replace blackhole default table ${ROUTE_TABLE}
}

# Delete the vpn routes only (don't touch blackhole routes)
delete_vpn_routes() {
	ip route show table ${ROUTE_TABLE} | grep -v blackhole | 
		xargs -I{} sh -c "ip route del {} table ${ROUTE_TABLE}"	
	ip -6 route show table ${ROUTE_TABLE} | grep -v blackhole | 
		xargs -I{} sh -c "ip -6 route del {} table ${ROUTE_TABLE}"	
}

# Delete all (flush) routes from custom route table.
# This includes VPN and blackhole routes.
delete_all_routes() {	
	ip route flush table ${ROUTE_TABLE}
	ip -6 route flush table ${ROUTE_TABLE}
}

### END OF FUNCTIONS ###

# If configuration variables are not present, source config file from the PWD.
if [ -z "${MARK}" ]; then
	echo "$(date +'%a %b %d %H:%M:%S %Y') split-vpn: Loading configuration from ${PWD}/vpn.conf."
	source ./vpn.conf
fi

# If no provider was given, assume openvpn for backwards compatibility.
if [ -z "${VPN_PROVIDER}" ]; then
	VPN_PROVIDER="openvpn"
fi

# Use the iptables script stored in the directory of this script.
iptables_script="$(dirname "$0")/add-vpn-iptables-rules.sh"

# Construct the ip rule.
ip_rule="fwmark ${MARK} lookup ${ROUTE_TABLE} pref ${PREF}"

# Startup blackholes to remove.
startup_blackholes="0.0.0.0/1 128.0.0.0/1 ::/1 8000::/1"

# Initialize gateway routes to undefined.
gateway_ipv4=undefined
gateway_ipv6=undefined

# Assume 1 second timer for watcher if not defined.
if [ -z "${WATCHER_TIMER}" ]; then
	WATCHER_TIMER=1
fi

# Get tunnel and state from script arguments, or use environment
# variables if they exist for openvpn. 
if [ ${VPN_PROVIDER} = "openvpn" -a -n "${dev}" ]; then
	tun="${dev}"
else
	tun="$1"
fi
if [ ${VPN_PROVIDER} = "openvpn" -a -n "${script_type}" ]; then
	state="${script_type}"
else
	state="$2"
fi

# When OpenVPN calls this script, script_type is either up or down.
# This script might also be manually called with force-down to force shutdown 
# regardless of KILLSWITCH settings.
if [ "$state" = "force-down" ]; then
	kill_rule_watcher
	delete_all_routes
	sh ${iptables_script} force-down $tun
	echo "Forced $tun down. Deleted killswitch and rules."
elif [ "$state" = "pre-up" ]; then
	add_blackhole_routes
	sh ${iptables_script} pre-up $tun
	run_rule_watcher
elif [ "$state" = "up" ]; then
	add_blackhole_routes
	if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
		add_vpn_routes
	fi
	add_gateway_route
	sh ${iptables_script} up $tun
	run_rule_watcher
else
	if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
		delete_vpn_routes
	fi
	# Only delete the rules if remove killswitch option is set.
	if [ "${REMOVE_KILLSWITCH_ON_EXIT}" = 1 ]; then
		# Kill the rule checking daemon.
		kill_rule_watcher
		if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
			delete_all_routes
		fi
		sh ${iptables_script} down $tun
	fi
fi
