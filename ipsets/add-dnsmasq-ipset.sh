#!/bin/sh
# This script creates IPv4 and IPv6 IP sets and adds them to a dnsmasq 
# configuration for the domains configured in the config file. 
# dnsmasq will add the IP of these domains to the IP sets when they are
# looked up.
#
# The script will also add a cron job to clear the IP sets at a predefined
# time and reload the dns cache. The predefined time is configured below.
#
# This script expects the config files be placed in the same folder.
set -e

create_ipsets() {
	# Create forced and exempt IPv4 and IPv6 ipsets
	ipset -! create ${PREFIX}FORCED list:set
	ipset -! create ${PREFIX}EXEMPT list:set
	ipset -! create ${PREFIX}FORCED4 hash:net
	ipset -! create ${PREFIX}FORCED6 hash:net family inet6
	ipset -! create ${PREFIX}EXEMPT4 hash:net
	ipset -! create ${PREFIX}EXEMPT6 hash:net family inet6

	# Add IPv4 and IPv6 ipsets into a combined list ipset
	ipset -! add ${PREFIX}FORCED ${PREFIX}FORCED4
	ipset -! add ${PREFIX}FORCED ${PREFIX}FORCED6
	ipset -! add ${PREFIX}EXEMPT ${PREFIX}EXEMPT4
	ipset -! add ${PREFIX}EXEMPT ${PREFIX}EXEMPT6
}

add_ipset_domains() {
	# Add domain and ipset into a map using JSON.
	# Map[config_folder]["domains"][domain] = [ipset1, ipset2, ...]
	# Map[config_folder]["forward_servers"] = $FORWARD_SERVERS
	for domain in ${FORCED_DOMAINS}; do
		ipsets_map=$(echo "$ipsets_map" | 
			jq '(.["'"$DNSMASQ_CONFIG_FOLDER"'"]["domains"]["'"$domain"'"] += 
					["'"${PREFIX}FORCED4"'","'"${PREFIX}FORCED6"'"])')
	done
	for domain in ${EXEMPT_DOMAINS}; do
		ipsets_map=$(echo "$ipsets_map" | 
			jq '(.["'"$DNSMASQ_CONFIG_FOLDER"'"]["domains"]["'"$domain"'"] += 
					["'"${PREFIX}EXEMPT4"'","'"${PREFIX}EXEMPT6"'"])')
	done
	if [ -n "$FORWARD_SERVERS" ]; then
		ipsets_map=$(echo "$ipsets_map" | 
			jq '(.["'"$DNSMASQ_CONFIG_FOLDER"'"]["forward_servers"] = 
					"'"$FORWARD_SERVERS"'")')
	fi

	# Add restart command into a unique list
	restart_commands=$(echo "$restart_commands" | jq '. += ["'"$RESTART_COMMAND"'"] | unique')

	# Flush ipsets
	ipset flush ${PREFIX}FORCED4 && ipset flush ${PREFIX}FORCED6
	ipset flush ${PREFIX}EXEMPT4 && ipset flush ${PREFIX}EXEMPT6
}

add_cron_job() {	
	# Add cron_time and prefix into a map using JSON
	# Map[cron_time].prefixes = [prefix1, prefix2, ...]
	# Map[cron_time].commands = [reload_cmd1, reload_cmd2, ...]
	jobs_map=$(echo "$jobs_map" | 
			jq '
				.["'"$CRON_TIME"'"]["prefixes"] += ["'"${PREFIX}"'"] |	
				.["'"$CRON_TIME"'"]["commands"] += ["'"${RELOAD_COMMAND}"'"] |
				.["'"$CRON_TIME"'"]["commands"] |= unique
				')
}

write_jobs_to_cronfile() {
	# Combine commands with the same cron_time and write each
	# one to the cron file.
	rm -f "$cron_file"
	username=""
	if [ $version -gt 1 ]; then
		username="root "
	fi
    ipset_bin="$(which ipset)"
	echo "$jobs_map" | jq -r 'keys[]' | while read -r cron_time; do
		commands=$(echo "$jobs_map" | 
			jq -r '[
					([.["'"${cron_time}"'"]["prefixes"][] | "'"${username}"''"${ipset_bin}"' flush \(.)FORCED4; '"${ipset_bin}"' flush \(.)FORCED6; '"${ipset_bin}"' flush \(.)EXEMPT4; '"${ipset_bin}"' flush \(.)EXEMPT6"] | join("; ")),
					(.["'"${cron_time}"'"]["commands"] | join("; "))
					] | join("; ")
					')
		echo "${cron_time} ${commands}" >> "$cron_file"
	done
	echo "add-dnsmasq-ipsets: Saving cron jobs to $cron_file"

	# UnifiOS 2 and up have cron running as a systemd service and watches the cron.d folder automatically
	# Only need to reload cron for UnifiOS < 2
	if [ $version -lt 2 ]; then
		/etc/init.d/crond reload "$cron_file"
	fi
}

write_ipsets_to_config() {
	# Write ipsets config to config location
	echo "$ipsets_map" | jq -r 'keys[]' | while read -r config_location; do
		config="${config_location}/ipsets.conf"

		# Add ipset list to dnsmasq config
		echo "add-dnsmasq-ipsets: Saving dnsmasq config to ${config}"
		echo "$ipsets_map" | jq -r '.["'"$config_location"'"]["domains"] | keys[] as $k | "ipset=/\($k)/\(.[$k] | unique | join(","))"' > "$config"
       
		# Add forward server to dnsmasq config 
		forward_servers="$(echo "$ipsets_map" | jq -r '.["'"$config_location"'"]["forward_servers"] // empty')"
		if [ -n "$forward_servers" ]; then
			for forward_server in $forward_servers; do
				echo "add-dnsmasq-ipsets: Adding DNS forward $forward_server"
				echo "server=/./$forward_server" >> "$config"
			done
			echo "add-subnet=32,128" >> "$config"
			echo "no-resolv" >> "$config"
		fi
	done

	# Restart dns server to apply new configuration
	echo "$restart_commands" | jq -r '.[]' | while read -r comm; do
		echo "add-dnsmasq-ipsets: Running restart command: $comm"
		eval "$comm" || true
	done
}

restart_commands="[]"
ipsets_map="{}"
jobs_map="{}"
cron_file="/etc/cron.d/ipset_cleanup"
version=$(ubnt-device-info firmware | sed -E s/"^([0-9]+)\..*$"/"\1"/g)
if [ -z "$version" ]; then
	version=1
fi

for conf in "$(dirname "$0")"/*.conf; do
	echo "add-dnsmasq-ipsets: Loading configuration from ${conf}"
	unset FORCED_DOMAINS EXEMPT_DOMAINS FORWARD_SERVERS
	. "${conf}"
	create_ipsets
	add_ipset_domains
	add_cron_job
done
write_ipsets_to_config
write_jobs_to_cronfile
