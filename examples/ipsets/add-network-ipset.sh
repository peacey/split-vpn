#!/bin/sh
# This script will create IPv4 and IPv6 ipsets named IPSET_NAME4 and IPSET_NAME6,
# and will add the networks defined in the file $LIST_FILE to these ipsets.
# A convenience ipset named IPSET_NAME is also created that contains both sets.

# Set the ipset name and list file location
IPSET_NAME="VPN_LIST"
LIST_FILE="/etc/split-vpn/ipsets/networklist.txt"

# Flush the ipsets (delete everything in them)
ipset -! flush ${IPSET_NAME}4 >/dev/null 2>&1
ipset -! flush ${IPSET_NAME}6 >/dev/null 2>&1

# Create the ipsets
ipset -! create ${IPSET_NAME} list:set
ipset -! create ${IPSET_NAME}4 hash:net
ipset -! create ${IPSET_NAME}6 hash:net family inet6
ipset -! add ${IPSET_NAME} ${IPSET_NAME}4
ipset -! add ${IPSET_NAME} ${IPSET_NAME}6

# Add networks from list file
for net in $(cat "${LIST_FILE}"); do
	isIPv6=$(echo ${net} | grep -q ':' && echo 1 || echo 0)
	if [ ${isIPv6} = 1 ]; then
		ipset add ${IPSET_NAME}6 ${net}
	else
		ipset add ${IPSET_NAME}4 ${net}
	fi
done
