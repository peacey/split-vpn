#!/bin/sh
# This script adds/removes the VPN routes and calls the iptables vpn script.
# This script is called by openvpn's up and down hooks.

# Set -e shell option to exit if any error is encountered
set -e 

### Functions ###

# Helper function to log with prefix
logf() {
	echo "[$(date)] split-vpn: $@"
}

# Helper function to check if a function is defined
fn_exists() {
	type $1 2>/dev/null | head -n1 | grep -q function
	[ $? = 0 ]
}

# Kill the rule watcher (previously running up/down script for the tunnel device).
kill_rule_watcher() {
	for p in $(pgrep -f "sh.*$(basename "$0") $tun .*$nickname"); do
		if [ $p != $$ ]; then
			kill -9 $p
		fi
	done
	# Only delete the rules if not in pre-up or up hook
	if [ "$state" != "pre-up" -a "$state" != "up" ]; then
		ip rule del $ip_rule >/dev/null 2>&1 || true
		ip -6 rule del $ip_rule >/dev/null 2>&1 || true
	fi
}

# Run the rule watcher which will be used to re-add the policy-based ip rules
# if removed. Rule watcher keeps this script running in the background.
run_rule_watcher() {
	kill_rule_watcher
	(while :; do
		ip rule show fwmark ${MARK} | grep ${MARK} >/dev/null 2>&1 || 
			(ip rule add $ip_rule && echo "Readded IPv4 rule.")
		ip -6 rule show fwmark ${MARK} | grep ${MARK} >/dev/null 2>&1 || 
			(ip -6 rule add $ip_rule && echo "Readded IPv6 rule.")
		if [ "${REMOVE_STARTUP_BLACKHOLES}" = 1 ]; then
			for route in ${startup_blackholes}; do
				ip route del blackhole "$route" >/dev/null 2>&1 &&
					echo "Removed blackhole ${route}."
			done
		fi
		if [ "${GATEWAY_TABLE}" = "auto" ]; then
			add_gateway_routes || true
		fi
		if [ "${VPN_PROVIDER}" = "nexthop" ]; then
			add_nexthop_routes || true
		fi
 		sleep ${WATCHER_TIMER}
	done) 2>&1 | (while read -r LINE; do logf "${LINE}"; done) > rule-watcher.log &
}

# Get the gateway from the UDM/P custom WAN table..
# 201 = Ethernet table, 202 = SFP+ table, 203 = U-LTE.
get_gateway() {
	tables=""
	if [ "${GATEWAY_TABLE}" = "auto"  ]; then
		tables=$(ip rule | sed -En s/".*from all lookup (20[123]).*"/"\1"/p | tail -n1)
	elif [ -n "${GATEWAY_TABLE}" ]; then
		tables="${GATEWAY_TABLE}"
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
		if [ -x "$(command -v bc)" ]; then	
			num_binary_bits=$(echo "ibase=10; obase=2; ${octet}"| bc | sed 's/0//g')
		elif [ -x "$(command -v bash)" ]; then
			num_binary_bits=$(bash -c 'D2B=({0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}); echo ${D2B['"${octet}"']}' | sed 's/0//g')
		fi
		num_bits=$(expr $num_bits + ${#num_binary_bits})
	done
	echo "${num_bits}"
}

# Add the VPN routes to the custom table for OpenVPN provider.
# OpneVPN will pass route_* and dev environment variables to this script.
add_openvpn_routes() {
	# Flush route table first
	delete_vpn_routes

	# Add default route to VPN
	if [ "${DISABLE_DEFAULT_ROUTE}" != "1" ]; then
		if [ -n "${route_vpn_gateway}" ]; then
			ip route replace 0.0.0.0/1 via ${route_vpn_gateway} dev ${dev} table ${ROUTE_TABLE}
			ip route replace 128.0.0.0/1 via ${route_vpn_gateway} dev ${dev} table ${ROUTE_TABLE}
		else
			logf "WARNING: OpenVPN did not pass the VPN gateway so connection might not work. Please pass the option '--redirect-gateway def1' to the openvpn command when you run it, or manually set route_vpn_gateway in your vpn.conf."
			ip route replace 0.0.0.0/1 dev ${dev} table ${ROUTE_TABLE}
			ip route replace 128.0.0.0/1 dev ${dev} table ${ROUTE_TABLE}
		fi
		ip -6 route replace ::/1 dev ${dev} table ${ROUTE_TABLE}
		ip -6 route replace 8000::/1 dev ${dev} table ${ROUTE_TABLE}
	fi

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
		if [ -z "${cidr}" -o "$cidr" = "0" ]; then
			logf "Could not calculate CIDR for ${route_network_i}/${route_netmask_i}. Assuming 32."
			cidr=32
		fi
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
		if [ -n "${route_ipv6_gateway_i}" -a "${route_ipv6_gateway_i}" != "::" ]; then
			ip -6 route replace ${route_ipv6_network_i} via ${route_ipv6_gateway_i} dev ${dev} table ${ROUTE_TABLE}
		else
			ip -6 route replace ${route_ipv6_network_i} dev ${dev} table ${ROUTE_TABLE}
		fi
	done
}

add_nexthop_routes() {
	# Add nexthop routes to route table
	if [ -n "${VPN_ENDPOINT_IPV4}" ]; then
		ip route replace 0.0.0.0/1 via ${VPN_ENDPOINT_IPV4} dev ${tun} table ${ROUTE_TABLE}
		ip route replace 128.0.0.0/1 via ${VPN_ENDPOINT_IPV4} dev ${tun} table ${ROUTE_TABLE}
	fi
	if [ -n "${VPN_ENDPOINT_IPV6}" ]; then
		ip -6 route replace ::/1 via ${VPN_ENDPOINT_IPV6} dev ${tun} table ${ROUTE_TABLE}
		ip -6 route replace 8000::/1 via ${VPN_ENDPOINT_IPV6} dev ${tun} table ${ROUTE_TABLE}
	fi
}

# Add the VPN endpoint -> WAN gateway route.
add_gateway_routes() {
	if [ "${GATEWAY_TABLE}" = "disabled" ]; then
		return
	fi
	get_gateway
	if [ -n "${VPN_ENDPOINT_IPV4}" -a -n "${gateway_ipv4}" ]; then
		if [ "${gateway_ipv4}" != "${gateway_ipv4_old}" ]; then
			logf "Using IPv4 gateway from table ${current_table}: ${gateway_ipv4}."
			ip route replace ${VPN_ENDPOINT_IPV4} ${gateway_ipv4} table ${ROUTE_TABLE} || true
			ip route replace ${VPN_ENDPOINT_IPV4} ${gateway_ipv4} || true
		fi
	fi
	if [ -n "${VPN_ENDPOINT_IPV6}" -a -n "${gateway_ipv6}" ]; then
		if [ "${gateway_ipv6}" != "${gateway_ipv6_old}" ]; then
			logf "Using IPv6 gateway from table ${current_table}: ${gateway_ipv6}."
			ip -6 route replace ${VPN_ENDPOINT_IPV6} ${gateway_ipv6} table ${ROUTE_TABLE} || true
			ip -6 route replace ${VPN_ENDPOINT_IPV6} ${gateway_ipv6} || true
		fi
	fi
}

# Add blackhole routes so if VPN routes are deleted everything is rejected
# Helps to prevent leaks during VPN restarts.
add_blackhole_routes() {
	if [ "${DISABLE_BLACKHOLE}" = "1" ]; then
		delete_blackhole_routes
	else
		ip route replace blackhole default table ${ROUTE_TABLE}
		ip -6 route replace blackhole default table ${ROUTE_TABLE}
	fi
}

set_vpn_endpoint() {
	if [ "${VPN_PROVIDER}" = "openvpn" -a -n "${trusted_ip}" ]; then
		VPN_ENDPOINT_IPV4="${trusted_ip}"
	fi
	if [ "${VPN_PROVIDER}" = "openvpn" -a -n "${trusted_ip6}" ]; then
		VPN_ENDPOINT_IPV6="${trusted_ip6}"
	fi
	if [ "${VPN_PROVIDER}" = "openconnect" ]; then
		if [ -n "${VPNGATEWAY}" ]; then
			echo "${VPNGATEWAY}" | grep -q : && FAMILY=6 || FAMILY=4
			if [ "$FAMILY" = "4" ]; then
				VPN_ENDPOINT_IPV4="${VPNGATEWAY}"
			else
				VPN_ENDPOINT_IPV6="${VPNGATEWAY}"
			fi
		fi
	fi
	if [ "${VPN_PROVIDER}" = "external" ]; then
		# If wireguard, get endpoint from wireguard interface
		wg_endpoint=$(wg show "${tun}" endpoints 2>/dev/null | sed -En s/"^.*\s+\[?([0-9a-fA-F\.:]+)\]?:(.*)$"/"\1"/p | head -n1)
		if $(echo "${wg_endpoint}" | grep -q ':'); then
			VPN_ENDPOINT_IPV6="${wg_endpoint}"
			VPN_ENDPOINT_IPV4=""
		elif $(echo "${wg_endpoint}" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"); then
			VPN_ENDPOINT_IPV4="${wg_endpoint}"
			VPN_ENDPOINT_IPV6=""
		fi
	fi
	if [ -z "${VPN_ENDPOINT_IPV4}" -a -z "${VPN_ENDPOINT_IPV6}" ]; then
		logf "WARNING: No VPN endpoint found. If your VPN provider is external (wireguard) or nexthop, please set VPN_ENDPOINT_IPV4 or VPN_ENDPOINT_IPV6 to the VPN's IP in your vpn.conf and restart the VPN."
	fi
}

# Delete the vpn routes only (don't touch blackhole routes)
delete_vpn_routes() {
	ip route show table ${ROUTE_TABLE} | grep -v blackhole | cut -d' ' -f1 | 
		xargs -I{} sh -c "ip route del {} table ${ROUTE_TABLE}"	
	ip -6 route show table ${ROUTE_TABLE} | grep -v blackhole | cut -d' ' -f1 | 
		xargs -I{} sh -c "ip -6 route del {} table ${ROUTE_TABLE}"
}

# Delete the gateway routes
delete_gateway_routes() {
	if [ "${GATEWAY_TABLE}" = "disabled" ]; then
		return
	fi
	if [ -n "${VPN_ENDPOINT_IPV4}" ]; then
		ip route del "${VPN_ENDPOINT_IPV4}" table ${ROUTE_TABLE} >/dev/null 2>&1 || true
		ip route del "${VPN_ENDPOINT_IPV4}" >/dev/null 2>&1 || true
	fi
	if [ -n "${VPN_ENDPOINT_IPV6}" ]; then
		ip -6 route del "${VPN_ENDPOINT_IPV6}" table ${ROUTE_TABLE} >/dev/null 2>&1 || true
		ip -6 route del "${VPN_ENDPOINT_IPV6}" >/dev/null 2>&1 || true
	fi
}

# Delete the blackhole routes only
delete_blackhole_routes() {
	ip route show table ${ROUTE_TABLE} | grep blackhole | cut -d' ' -f-2 | 
		xargs -I{} sh -c "ip route del {} table ${ROUTE_TABLE}"
	ip -6 route show table ${ROUTE_TABLE} | grep blackhole | cut -d' ' -f-2 | 
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
CONFIG_FILE=""
if [ -z "${MARK}" ]; then
	CONFIG_FILE="${PWD}/vpn.conf"
	. ./vpn.conf
fi

# If no provider was given, assume openvpn for backwards compatibility.
if [ -z "${VPN_PROVIDER}" ]; then
	VPN_PROVIDER="openvpn"
fi

# Assume 1 second timer for watcher if not defined.
if [ -z "${WATCHER_TIMER}" ]; then
	WATCHER_TIMER=1
fi

# Assume auto for gateway table if not defined.
if [ -z "${GATEWAY_TABLE}" ]; then
	GATEWAY_TABLE="auto"
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

# Set nickname for nexthop invocation.
nickname=""
if [ "${VPN_PROVIDER}" = "nexthop" ]; then
	nickname="$3"
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

# Print the config being using
if [ -n "$CONFIG_FILE" ]; then
	logf "${tun} ${state}: Loading configuration from ${CONFIG_FILE}."
fi

set_vpn_endpoint

# When OpenVPN calls this script, script_type is either up or down.
# This script might also be manually called with force-down to force shutdown 
# regardless of KILLSWITCH settings.
if [ "$state" = "force-down" ]; then
	kill_rule_watcher
	delete_gateway_routes
	delete_all_routes
	sh ${iptables_script} force-down $tun
	logf "Forced ${tun} down. Deleted killswitch and rules."
	if fn_exists hooks_force_down; then
		hooks_force_down
	fi
elif [ "$state" = "pre-up" ]; then
	add_blackhole_routes
	sh ${iptables_script} pre-up $tun
	run_rule_watcher
	if fn_exists hooks_pre_up; then
		hooks_pre_up
	fi
elif [ "$state" = "up" ]; then
	add_blackhole_routes
	if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
		add_openvpn_routes
	fi
	if [ "${VPN_PROVIDER}" = "nexthop" ]; then
		delete_vpn_routes
		add_nexthop_routes
	fi
	add_gateway_routes
	sh ${iptables_script} up $tun
	run_rule_watcher
	if fn_exists hooks_up; then
		hooks_up
	fi
else
	if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
		delete_vpn_routes
	fi
	# Only delete the rules if remove killswitch option is set.
	if [ "${REMOVE_KILLSWITCH_ON_EXIT}" = 1 ]; then
		# Kill the rule checking daemon.
		kill_rule_watcher
		delete_blackhole_routes
		delete_gateway_routes
		if [ "${VPN_PROVIDER}" = "openvpn" -a "${script_context}" != "restart" ]; then
			delete_all_routes
		elif [ "${VPN_PROVIDER}" = "nexthop" ]; then
			delete_all_routes
		fi
		sh ${iptables_script} down $tun
	fi
	if fn_exists hooks_down; then
		hooks_down
	fi
fi
