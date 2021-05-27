#!/bin/sh
# This script adds/removes the VPN routes and calls the iptables vpn script.
# This script is called by openvpn's up and down hooks.

# Set -e shell option to exit if any error is encountered
set -e 

### Functions ###

# Kill the rule watcher (previously running up/down script for the tunnel device).
kill_rule_watcher() {
	for p in $(pgrep -f "/bin/sh.*$(basename "$0") ${dev}"); do
		if [ $p != $$ ]; then
			kill -9 $p
		fi
	done
	ip rule del $ip_rule &> /dev/null || true
	ip -6 rule del $ip_rule &> /dev/null || true
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
 		sleep 1
	done) > rule-watcher.log &
}

# Get the gateway from the UDMP custom WAN table. This function checks the active WAN.
# 202 = WAN2 table, 201 = WAN1 table on UDMP.
# TODO: Does the UDM (non-pro) use the same table numbers?
get_gateway() {
	if [ -z "${route_net_gateway_ip}" ] && [ -z "${route_net_gateway_dev}" ]; then
		for table in 201 202; do
			route_net_gateway_ip=$(ip route show table ${table} | grep "default.*via" | sed -E s/".* via ([0-9\.]+) .*"/"\1"/g)
			route_net_gateway_dev=$(ip route show table ${table} | grep "default.*dev" | sed -E s/".* dev ([^ ]+) .*"/"\1"/g)
			if [ -n "${route_net_gateway_ip}" ] || [ -n "${route_net_gateway_dev}" ]; then
				break
			fi
		done
	fi
	if [ -z "${route_net_gateway_ip}" ] && [ -z "${route_net_gateway_dev}" ]; then
		echo "$(date +'%a %b %d %H:%M:%S %Y') $(basename "$0"): No default gateway found."
	fi
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

# Add the VPN routes to the custom table.
add_vpn_routes() {
	# Flush route table first and get the current non-VPN gateway.
	delete_vpn_routes
	get_gateway

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
	if [ -n "${trusted_ip}" ]; then
		if [ -n "${route_net_gateway_ip}" ] && [ -n "${route_net_gateway_dev}" ]; then
			ip route replace ${trusted_ip}/32 via ${route_net_gateway_ip} dev ${route_net_gateway_dev} table ${ROUTE_TABLE}
		elif [ -n "${route_net_gateway_ip}" ]; then
			ip route replace ${trusted_ip}/32 via ${route_net_gateway_ip} table ${ROUTE_TABLE}
		elif [ -n "${route_net_gateway_dev}" ]; then
			ip route replace ${trusted_ip}/32 dev ${route_net_gateway_dev} table ${ROUTE_TABLE}
		fi
	fi
}

# Add blackhole routes so if VPN routes are deleted everything is rejected
# Helps to prevent leaks during VPN restarts.
add_blackhole_routes() {
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
	echo "Loading configuration from ${PWD}/vpn.conf."
	source ./vpn.conf
fi

# Use the iptables script stored in the directory of this script.
iptables_script="$(dirname "$0")/add-vpn-iptables-rules.sh"

# Construct the ip rule.
ip_rule="fwmark ${MARK} lookup ${ROUTE_TABLE} pref ${PREF}"

# Startup blackholes to remove
startup_blackholes="0.0.0.0/1 128.0.0.0/1 ::/1 8000::/1"

# When OpenVPN calls this script, script_type is either up or down.
# This script might also be manually called with force-down to force shutdown 
# regardless of KILLSWITCH settings.
if [[ "$2" = "force-down" ]]; then
	kill_rule_watcher
	delete_all_routes
	sh ${iptables_script} force-down $1
	echo "Forced $1 down. Deleted killswitch and rules."
elif [[ "$2" = "pre-up" ]]; then
	add_blackhole_routes
	sh ${iptables_script} up $1
	run_rule_watcher
elif [[ "${script_type}" = "up" ]]; then
	add_blackhole_routes
	if [ "${script_context}" != "restart" ]; then
		add_vpn_routes
	fi
	sh ${iptables_script} up ${dev}
	run_rule_watcher
else
	if [ "${script_context}" != "restart" ]; then
   		delete_vpn_routes
	fi
	# Only delete the rules if option is set.
	if [ "${REMOVE_KILLSWITCH_ON_EXIT}" = 1 ]; then
		# Kill the rule checking daemon.
		kill_rule_watcher
		if [ "${script_context}" != "restart" ]; then
                	delete_all_routes
        	fi
		sh ${iptables_script} down ${dev}
	fi
fi
