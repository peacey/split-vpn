#!/bin/sh
# This script adds/removes the VPN routes and calls the iptables vpn script.
# This script is called by openvpn's up and down hooks.

# Set -e shell option to exit if any error is encountered
set -e 

### Functions ###

# Kill the rule watcher (previously running up/down script for the tunnel device).
kill_rule_watcher() {
	for p in $(pgrep -f "$(basename "$0") ${dev}"); do
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
		sleep 1
	done) > rule-watcher.log &
}

# Get the gateway from the UDMP custom WAN table. This function checks the active WAN.
# 202 = WAN2 table, 201 = WAN1 table on UDMP.
# TODO: Does the UDM (non-pro) use the same table numbers?
get_gateway() {
	if [ -x ${route_net_gateway} ]; then
		route_net_gateway=$(ip route show default table 202 | cut -d' ' -f3)
		if [ -x ${route_net_gateway} ]; then
			route_net_gateway=$(ip route show default table 201 | cut -d' ' -f3)
		fi
	fi
	if [ -x ${route_net_gateway} ]; then
		echo "$(date +'%a %b %d %H:%M:%S %Y') updown.sh: No default gateway found."
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
	# Flush route table first and get the current non-VPN gateway
	delete_vpn_routes
	get_gateway

	# Add default route to VPN
	ip route replace 0.0.0.0/1 via ${route_vpn_gateway} table ${ROUTE_TABLE}
	ip route replace 128.0.0.0/1 via ${route_vpn_gateway} table ${ROUTE_TABLE}
	ip -6 route replace ::/1 dev ${dev} table ${ROUTE_TABLE}
	ip -6 route replace 8000::/1 dev ${dev} table ${ROUTE_TABLE}

	# Add VPN routes from environment variables supplied by OpenVPN
	# Only check a maximum of 1000 routes. Usually only get < 10.
	for i in $(seq 1 1000); do
		route_network_i=$(eval echo \$route_network_$i)
		route_gateway_i=$(eval echo \$route_gateway_$i)
		route_netmask_i=$(eval echo \$route_netmask_$i)
		if [ -x $route_network_i ]; then
			break
		fi
		cidr=$(netmask_to_cidr $route_netmask_i)
		if [[ "$cidr" = "32" ]]; then
			ip route replace ${route_network_i}/32 via ${route_gateway_i} table ${ROUTE_TABLE}
		else
			ip route replace ${route_network_i}/${cidr} dev ${dev} table ${ROUTE_TABLE}
		fi
	done
	for route in $(env | grep route_ipv6_network_ | cut -d'=' -f2); do
		ip -6 route replace ${route} dev ${dev} table ${ROUTE_TABLE}
	done
	if [ ! -x ${trusted_ip} -a ! -x ${route_net_gateway} ]; then
		ip route replace ${trusted_ip}/32 via ${route_net_gateway} table ${ROUTE_TABLE}
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
}

# Delete all (flush) routes from custom route table.
# This includes VPN and blackhole routes.
delete_all_routes() {	
	ip route flush table ${ROUTE_TABLE}
}

### END OF FUNCTIONS ###

# If configuration variables are not present, source config file from the PWD.
if [ -x ${MARK} ]; then
	echo "Loading configuration from ${PWD}/vpn.conf."
	source ./vpn.conf
fi

# Construct the ip rule
ip_rule="fwmark ${MARK} lookup ${ROUTE_TABLE} pref ${PREF}"

# When OpenVPN calls this script, script_type is either up or down.
# This script might also be manually called with force-down to force shutown 
# regardless of KILLSWITCH settings.
if [[ "$2" = "force-down" ]]; then
	kill_rule_watcher
	delete_all_routes
	sh /mnt/data/openvpn/add-vpn-iptables-rules.sh force-down $1
elif [[ "${script_type}" = "up" ]]; then
	add_blackhole_routes
	add_vpn_routes
	run_rule_watcher
	sh /mnt/data/openvpn/add-vpn-iptables-rules.sh up ${dev}
else
   	delete_vpn_routes
	# Only delete the rules if option is set
	if [ ${REMOVE_KILLSWITCH_ON_EXIT} = 1 ]; then
		# Kill the rule checking daemon
		kill_rule_watcher
		delete_all_routes
		sh /mnt/data/openvpn/add-vpn-iptables-rules.sh down ${dev}
	fi
fi
