#!/bin/sh
# This script sets up the pihole macvlan network on the VLAN configured 
# below. The pihole network will remain on the host namespace and will 
# run alongside the UDM/P's dnsmasq. 

## configuration variables:

# VLAN ID
VLAN=5

# IPv4 to assign to pihole network
IPV4="10.0.5.3"

# IPv6 to assign to pihole network
# Can be empty or commented out for no IPv6
IPV6="fd62:89a2:fda9:e23::2"

# Set this to a randomly generated MAC. 
# Use an online MAC address generator as not every combination is valid. 
MAC="1a:34:24:f2:a0:09"

# Set this to the interface(s) on which you want DNS TCP/UDP port 53 traffic
# re-routed through the pihole. Separate interfaces with spaces.
# e.g. "br0" or "br0 br1" etc.
FORCED_INTFC="br0"

# Container name
CONTAINER=pihole

# Set this to your pihole dnsmasq config location.
PIHOLE_CONFIG="/mnt/data/pihole/etc-dnsmasq.d"

# Enable this to redirect this port to port 80 on the IP above. 
# This allows you to set the pihole to use port 81 or some other
# port for the web, but be able to access it on port 80. 
REDIRECT_WEB_PORT=81

## END OF CONFIGURATION

LISTEN_IPS="$IPV4"
if [ -n "$IPV6" ]; then
	LISTEN_IPS="${LISTEN_IPS},${IPV6}"
fi

# set VLAN bridge promiscuous
ip link set br${VLAN} promisc on

# create macvlan bridge and add IPv4 IP
ip link add br${VLAN}pi link br${VLAN} type macvlan mode bridge
ip link set dev br${VLAN}pi address $MAC
ip addr replace ${IPV4}/32 dev br${VLAN}pi noprefixroute

# (optional) add IPv6 IP to macvlan bridge
if [ -n "${IPV6}" ]; then
	ip -6 addr replace ${IPV6} dev br${VLAN}pi noprefixroute
fi

# set macvlan bridge promiscuous and bring it up
ip link set br${VLAN}pi promisc on
ip link set br${VLAN}pi up

# Make dnsmasq not listen on this network
echo "except-interface=br${VLAN}pi" > /run/dnsmasq.conf.d/custom_interface.conf
kill -9 `cat /run/dnsmasq.pid`

# Add listen address to pihole dnsmasq
cat << EOF > "${PIHOLE_CONFIG}/03-interfaces.conf"
bind-dynamic
interface=br${VLAN}pi
except-interface=lo
listen-address=${LISTEN_IPS}
EOF

if podman container exists ${CONTAINER}; then
	podman start ${CONTAINER}
else
	echo "ERROR: Container $CONTAINER not found, make sure you set the proper name. You can ignore this error if it is your first time setting the container up"
fi

# Force DNS traffic to pihole
for intfc in ${FORCED_INTFC}; do
	if [ -d "/sys/class/net/${intfc}" ]; then
		for proto in udp tcp; do
			prerouting_rule="PREROUTING -i ${intfc} -p ${proto} ! -s ${IPV4} ! -d ${IPV4} --dport 53 -j DNAT --to ${IPV4}"
			iptables -t nat -C ${prerouting_rule} || iptables -t nat -A ${prerouting_rule}
			if [ -n "${IPV6}" ]; then
				prerouting_rule="PREROUTING -i ${intfc} -p ${proto} ! -s ${IPV6} ! -d ${IPV6} --dport 53 -j DNAT --to [${IPV6}]"
				ip6tables -t nat -C ${prerouting_rule} || ip6tables -t nat -A ${prerouting_rule}
			fi
		done
	fi
done

# Add DNAT rule to redirect web port
if [ -n "$REDIRECT_WEB_PORT" ]; then
	prerouting_rule="PREROUTING -p tcp -d $IPV4 --dport 80 -j DNAT --to ${IPV4}:${REDIRECT_WEB_PORT}"
	iptables -t nat -C ${prerouting_rule} || iptables -t nat -A ${prerouting_rule}
	if [ -n "$IPV6" ]; then
		prerouting_rule="PREROUTING -p tcp -d $IPV6 --dport 80 -j DNAT --to [$IPV6]:${REDIRECT_WEB_PORT}"
		ip6tables -t nat -C ${prerouting_rule} || ip6tables -t nat -A ${prerouting_rule}
	fi
fi
