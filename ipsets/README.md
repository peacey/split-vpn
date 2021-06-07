## How to force domains

The built-in dnsmasq server on the UDM/P can be set up to add the IPs of domains to a kernel IP set as soon as they are looked up. The VPN script can be configured to force these IP sets through the VPN (or exempt them). Configured together, this allows for domains to be forced through the VPN (or exempt).

This configuration is supported on both the built-in dnsmasq or pihole (which uses it's own dnsmasq). If you are using pihole, it needs to run in the host network namespace. See [the instructions here](../pihole-host-mode/README.md) for how to run pihole in the host network namespace.

These instructions assume you have already installed the VPN script according to the instructions [here](https://github.com/peacey/split-vpn/blob/main/README.md#how-do-i-use-this).

## How to configure dnsmasq or pihole

1. Download the ipset script into `/mnt/data/split-vpn/ipsets`.
	```sh
	cd /mnt/data/split-vpn
	mkdir ipsets
	curl -L https://github.com/peacey/split-vpn/archive/main.zip | unzip - "*/ipsets/*" -o -j -d ipsets && chmod +x ipsets/*.sh
	```
2. Copy the sample ipset config file. 
	```sh
	cd ipsets
	cp VPN_domains.conf.sample VPN_domains.conf
	```
3. Edit the `VPN_domains.conf` file with your desired settings. 
	* If you are using pihole on the UDM instead of the built-in dnsmasq server, then uncomment the pihole settings and comment out the dnsmasq settings. The pihole container must be running in host network mode. See [the instructions here](../pihole-host-mode/README.md).
4. Run `./add-dnsmasq-ipsets.sh` and make sure there are no errors. 
	* At this point, you can test if the ipsets and dns server are set up correctly by following the instructions [below](#how-to-test-if-the-dns-server-is-setup-correctly). 
5. Modify your `vpn.conf` file for your VPN client. 
	1. If you want to force these domain restrictions on ALL clients not just VPN-forced ones, then set:
		```sh
		FORCED_IPSETS="VPN_FORCED:dst"
		EXEMPT_IPSETS="VPN_EXEMPT:dst"
		```
	2. If you want to force different domain sets to different clients or VLANs, see the instructions [below](#how-can-I-force-different-domain-sets-to-different-clients).
	3. Note that VPN-forced clients must use your dnsmasq or pihole address as their DNS for the domain-forcing to work, so make sure `DNS_IPV4_IP` is not set to DHCP. If clients will bypass your DHCP options, you should set `DNS_IPV4_IP/DNS_IPV6_IP` to your DNS server address (i.e. the UDMP address for local dnsmasq, or pihole address), and `DNS_IPV4_INTERFACE/DNS_IPV6_INTERFACE` to the bridge interface of that address (brX where X is the VLAN number). 
6. Restart the VPN client to apply the new configuration.  
7. If you are using a boot script (`/mnt/data/on_boot.d/99-run-vpn.sh`), modify it and add the following lines before you load the configuration for your VPN.
	```sh
	# Add dnsmasq 
	/mnt/data/split-vpn/ipsets/add-dnsmasq-ipsets.sh
	```


## How can I force different domain sets to different clients?
1. Copy the sample ipset config to as many configurations as you want, but give each one a different prefix. For example:
	```sh
	cd /mnt/data/split-vpn/ipsets
	cp VPN_domains.conf.sample VPN2_domains.conf
	cp VPN_domains.conf.sample VPN3_domains.conf
	```
2. Modify each domain set configuration and make sure to set a unique `PREFIX` in each config.
3. Use the `CUSTOM_FORCED_RULES_IPV4/IPV6` and `CUSTOM_EXEMPT_RULES_IPV4/IPV6` settings to choose which domain sets to force/exempt to which clients. 
	<details> 
	<summary>Click here for some examples.</summary>
	
	* To force by Source VLAN or Interface:
		```
		CUSTOM_FORCED_RULES_IPV4="
			-m set --match-set VPN_FORCED dst -i br6
			-m set --match-set VPN2_FORCED dst -i br7
		"
		CUSTOM_EXEMPT_RULES_IPV4="
			-m set --match-set VPN_EXEMPT dst -i br6
			-m set --match-set VPN2_EXEMPT dst -i br7
		"
		CUSTOM_FORCED_RULES_IPV6="
			-m set --match-set VPN_FORCED dst -i br6
			-m set --match-set VPN2_FORCED dst -i br7
		"
		CUSTOM_EXEMPT_RULES_IPV6="
			-m set --match-set VPN_EXEMPT dst -i br6
			-m set --match-set VPN2_EXEMPT dst -i br7
		"
		```
	* To force by Source IP
		```
		CUSTOM_FORCED_RULES_IPV4="
			-m set --match-set VPN_FORCED dst -s 192.168.1.1
			-m set --match-set VPN2_FORCED dst -s 192.168.1.2
		"
		CUSTOM_EXEMPT_RULES_IPV4="
			-m set --match-set VPN_EXEMPT dst -s 192.168.1.1
			-m set --match-set VPN2_EXEMPT dst -s 192.168.1.2
		"
		CUSTOM_FORCED_RULES_IPV6="
			-m set --match-set VPN_FORCED dst -s fd00::2
			-m set --match-set VPN2_FORCED dst -s fd00::3
		"
		CUSTOM_EXEMPT_RULES_IPV6="
			-m set --match-set VPN_EXEMPT dst -s fd00::2
			-m set --match-set VPN2_EXEMPT dst -s fd00::3
		"
		```
	* To force by MAC
		```
		CUSTOM_FORCED_RULES_IPV4="
			-m set --match-set VPN_FORCED dst -m mac --mac-source xx:xx:xx:xx:xx:xx
			-m set --match-set VPN2_FORCED dst -m mac --mac-source yy:yy:yy:yy:yy:yy
		"
		CUSTOM_EXEMPT_RULES_IPV4="
			-m set --match-set VPN_EXEMPT dst -m mac --mac-source xx:xx:xx:xx:xx:xx
			-m set --match-set VPN2_EXEMPT dst -m mac --mac-source yy:yy:yy:yy:yy:yy
		"
		CUSTOM_FORCED_RULES_IPV6="
			-m set --match-set VPN_FORCED dst -m mac --mac-source xx:xx:xx:xx:xx:xx
			-m set --match-set VPN2_FORCED dst -m mac --mac-source yy:yy:yy:yy:yy:yy
		"
		CUSTOM_EXEMPT_RULES_IPV6="
			-m set --match-set VPN_EXEMPT dst -m mac --mac-source xx:xx:xx:xx:xx:xx
			-m set --match-set VPN2_EXEMPT dst -m mac --mac-source yy:yy:yy:yy:yy:yy
		"
		```
	* You can mix different MAC, IP, VLAN custom rules together, just make sure to group them in the same variable. 
	</details>

## How to test if the dns server is setup correctly
1. After running `add-dnsmasq-ipsets.sh`, IP sets VPN_FORCED and VPN_EXEMPT, and their IPv4 and IPv6 versions, will be created (assuming you set `PREFIX=VPN` in the domains config).
2. Your DNS server should now be setup to add domains to these IP sets as they are looked up. 
3. Test if your DNS server is set up correctly by browsing to one of the FORCED or EXEMPT domains from your client, then run the following commands to check if the IP sets are being updated by your DNS server:
	```sh
	# For IPv4 sets
	ipset list VPN_FORCED4
	ipset list VPN_EXEMPT4
	# For IPv6 sets
	ipset list VPN_FORCED6
	ipset list VPN_EXEMPT6
	```
4. If you see the IPs of the domains you are forcing/exempting, then your DNS server and ipset configuration is set up correctly. 
5. Continue with Step 5 in the [instructions above](#how-to-configure-dnsmasq-or-pihole) if you haven't completed them yet.
