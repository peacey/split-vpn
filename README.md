# split-vpn
A split tunnel VPN script for the UDM/P.

## What is this?

This is a helper script for the OpenVPN client on the UDMP that creates a split tunnel for the VPN connection, and forces configured clients through the VPN instead of the default WAN. This is accomplished by marking every packet of the forced clients with an iptables firewall mark (fwmark), adding the VPN routes to a custom routing table, and using a policy-based routing rule to direct the marked traffic to the custom table. 

## Features

* Force traffic to the VPN based on source interface (VLAN), MAC address, or IP address.
* Exempt sources from the VPN based on IP, MAC address, or IP:port combination. This allows you to force whole VLANs through by interface, but then selectively choose clients from that VLAN, or specific services on forced clients, to exclude from the VPN.
* Exempt destinations from the VPN by IP. This allows VPN-forced clients to communicate with the LAN or other VLANs.
* Port forwarding on the VPN side to local clients (not all VPN providers give you ports).
* Redirect DNS for VPN traffic to either an upstream DNS server or a local server like pihole, or block DNS requests completely.
* Built-in kill switch via iptables and blackhole routing.
* Works across IP changes and network restarts. 
* Can be used with multiple openvpn instances with separate configurations for each. This allows you to force different clients through different VPN servers. 
* IPv6 support for all options.
* Run on boot support via UDM-Utilities boot script.

## Compatibility

This script is designed to be run on the UDM-Pro. It has only been tested on version 1.8.6, however other versions should work. This has not yet been tested on the UDM (non-pro). Please submit a bug report if you use this on a different version and encounter issues. 

## How do I use this?

<details>
  <summary>Click here to see the instructions.</summary>

1. SSH into the UDM/P (assuming it's on 192.168.1.254).

    ```sh
    ssh root@192.168.1.254
    ```
    
2. Download the scripts package and extract it to `/mnt/data/openvpn`.

    ```sh
    cd /mnt/data
    mkdir /mnt/data/openvpn
    curl -sL https://github.com/peacey/split-vpn/archive/main.zip | unzip - "*/openvpn/*" -j -d openvpn && chmod +x openvpn/*.sh
    ```
    
3. Create a directory for your VPN provider's openvpn configuration files, and copy your VPN's configuration files (certificates, config, password files, etc) and the sample vpn.conf from `/mnt/data/openvpn/vpn.conf.sample`. NordVPN is used below as an example. 

    ```sh
    mkdir /mnt/data/openvpn/nordvpn
    cd /mnt/data/openvpn/nordvpn
    curl https://downloads.nordcdn.com/configs/files/ovpn_legacy/servers/us-ca12.nordvpn.com.udp1194.ovpn --out nordvpn.ovpn
    cp /mnt/data/openvpn/vpn.conf.sample /mnt/data/openvpn/nordvpn/vpn.conf
    ```
    
4. If your VPN provider uses a username/password, put them in a `username_password.txt` file in the same directory as the configuration with the username on the first line and password on the second line. Then either: 
    * Edit your VPN provider's openvpn config you downloaded in step 3 to reference the username_password.txt file by adding/changing this directive: `auth-user-pass username_password.txt`.
    * Use the `--auth-user-pass username_password.txt` option when you run openvpn below in step 6 or 8. 
    
    NOTE: The username/password for openvpn are usually given to you in a file or in your VPN provider's online portal. They are usually not the same as your login to the VPN. 
5. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables). 
6. Run OpenVPN in the foreground to test if everything is working properly.

    ```sh
    openvpn --config nordvpn.ovpn \
            --route-noexec \
            --up /mnt/data/openvpn/updown.sh \
            --down /mnt/data/openvpn/updown.sh \
            --script-security 2
    ```
    
7. If the connection works, check each client to make sure they are on the VPN by doing the following.

    * Check if you are seeing the VPN IPs when you visit http://whatismyip.host/. You can also test from command line, by running the following commands from your clients. Make sure you are not seeing your real IP anywhere, either IPv4 or IPv6.
    
      ```sh
      curl -4 ifconfig.co
      curl -6 ifconfig.co
      ```
        
      If you are seeing your real IPv6 address above, make sure that you are forcing your client through IPv6 as well as IPv4, by forcing through interface, MAC address, or the IPv6 directly. If IPv6 is not supported by your VPN provider, the IPv6 check will time out and not return anything. You should never see your real IPv6 address. 

    * Check for DNS leaks with the Extended Test on https://www.dnsleaktest.com/. If you see a DNS leak, try redirecting DNS with the `DNS_IPV4_IP` and `DNS_IPV6_IP` options, or set `DNS_IPV6_IP="REJECT"` if your VPN provider does not support IPv6. 
    * Check for WebRTC leaks in your browser by visiting https://browserleaks.com/webrtc. If WebRTC is leaking your IPv6 IP, you need to disable WebRTC in your browser (if possible), or disable IPv6 completely by disabling it directly on your client or through the UDMP network settings for the client's VLAN.
    
8. If everything is working properly, stop the OpenVPN client by pressing Ctrl+C, and then run it in the background with the following command. You can modify the command to change `--ping-restart` or other options as needed. The only requirement is that you run updown.sh script as the up/down script and `--route-noexec` to disable OpenVPN from adding routes to the default table instead of our custom one.

    ```sh
    nohup openvpn --config nordvpn.ovpn \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --script-security 2 \
                  --ping-restart 15 \
                  --mute-replay-warnings > openvpn.log &
    ```
    
9. Now you can exit the UDM/P. If you would like to start the VPN client at boot, please read on to the next section. 
10. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the UDMP settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

</details>

## How do I run this at boot?

<details>
  <summary>Click here to see the instructions.</summary>
  
  You can use [UDM Utilities Boot Script](https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script) to run the VPN script at boot. The boot script survives across firmware upgrades too. 
  
1. Set-up UDM Utilities Boot Script by following the instructions [here](https://github.com/boostchicken/udm-utilities/blob/master/on-boot-script/README.md).
  
2. Create a new file under `/mnt/data/on_boot.d/run-vpn.sh` and fill it with the following. 

    ```sh
    #!/bin/sh
    # Load configuration and run openvpn
    cd /mnt/data/openvpn/nordvpn
    source ./vpn.conf
    /mnt/data/openvpn/updown.sh ${DEV} pre-up &> pre-up.log
    nohup openvpn --config nordvpn.ovpn \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --dev-type tun --dev ${DEV} \
                  --script-security 2 \
                  --ping-restart 15 \
                  --mute-replay-warnings &> openvpn.log &
    ```

    Remember to modify the `cd` line and the `--config` openvpn option to point to your config. Comment out the `updown.sh` line if you want the iptables kill switch to not be activated until after the VPN connects (not recommended).

3. Run `chmod +x /mnt/data/on_boot.d/run-vpn.sh` to give the script execute permissions. 
4. That's it. Now the VPN will start at every boot. 
5. Note that there is a short period between when the UDMP starts and when this script runs. This means there is a few seconds when the UDMP starts up when your forced clients **WILL** have access to your WAN and might leak their real IP, because the kill switch has not been activated yet. Read step 6 to see how to solve this problem and block Internet access until after this script runs. After the script runs, forced clients will not be able to access your WAN even if openvpn crashes or restarts (see the [REMOVE_KILLSWITCH_ON_EXIT](#configuration-variables) option below).
6. **OPTIONAL:** If you want to ensure that there is no Internet access BEFORE this script runs at boot, you can add blackhole static routes in the Unifi Settings that will block all Internet access until they are removed by this script. The blackhole routes will be removed when this script starts to restore Internet access only after the killswitch has been activated. If you want to do this for maximum protection at boot up, follow these instructions:

    a. Go to your Unifi Network Settings, and add the following static routes. If you're using the New Settings, this is under Advanced Features -> Advanced Gateway Settings -> Static Routes. For Old Settings, this is under Settings -> Routing and Firewall -> Static Routes. Add these routes which cover all IP ranges:
    
      1. **Name:** VPN Blackhole. **Destination:** 0.0.0.0/1. **Static Route Type:** Black Hole. **Enabled.**
      2. **Name:** VPN Blackhole. **Destination:** 128.0.0.0/1. **Static Route Type:** Black Hole. **Enabled.**
      3. **Name:** VPN Blackhole. **Destination:** ::/1. **Static Route Type:** Black Hole. **Enabled.**
      4. **Name:** VPN Blackhole. **Destination:** 8000::/1. **Static Route Type:** Black Hole. **Enabled.**
      
    b. In your vpn.conf, set the option `REMOVE_STARTUP_BLACKHOLES=1`. This is required or else the script will not delete the blackhole routes at startup, and you will not have Internet access on ANY client, not just the VPN-forced clients until you delete the blackhole routes manually or disable them in the Unifi Settings.
    
    c. In your run script above, make sure you did NOT comment out the `updown.sh pre-up` line. That is the line that removed the blackhole routes at startup.
    
    d. Note that once you do this, you will lose Internet access for ALL clients until you run the VPN run script above. The script stays running in the background to monitor if the the blackhole routes are added by the system again (which happens when your IP changes or when settings are changed). The blackhole routes will be deleted immediately when they're added.
  
</details>

## FAQ
<details>
  <summary>Can I route clients to different VPN servers?</summary>
  
  * Yes you can. Simply make a separate directory for each VPN server, and give them each a vpn.conf file with the clients you wish to force through them. Make sure the options `ROUTE_TABLE`, `MARK`, `PREFIX`, `PREF`, and `DEV` are unique for each `vpn.conf` file so the different VPN servers don't share the same tunnel device, route table, or fwmark. 
  
  * Afterwards, modify your run script like so (in this example, we are using Mullvad and NordVPN). Note that you need to cd into the correct directory for each different VPN server before running the openvpn command so that the correct config file is used for each and a unique TUN device is passed to openvpn.
  
    ```sh
    #!/bin/sh

    # Load configuration for mullvad and run openvpn
    cd /mnt/data/openvpn/mullvad
    source ./vpn.conf
    /mnt/data/openvpn/updown.sh ${DEV} pre-up &> pre-up.log
    nohup openvpn --config mullvad.conf \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --script-security 2 \
                  --dev-type tun --dev ${DEV} \
                  --ping-restart 15 \
                  --mute-replay-warnings > openvpn.log &

    # Load configuration for nordvpn and run openvpn
    cd /mnt/data/openvpn/nordvpn
    source ./vpn.conf
    /mnt/data/openvpn/updown.sh ${DEV} pre-up &> pre-up.log
    nohup openvpn --config nordvpn.ovpn \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --script-security 2 \
                  --dev-type tun --dev ${DEV} \
                  --ping-restart 15 \
                  --mute-replay-warnings > openvpn.log &
    ```

</details>

<details>
  <summary>How do I safely shutdown the VPN?</summary>
  
  * Simply send the openvpn process the TERM signal. Killswitch and iptables rules will only be removed if the option `REMOVE_KILLSWITCH_ON_EXIT` is set to 1.
  
    1. If you want to kill all openvpn instances.

        ```sh
        killall -TERM openvpn
        ```

    2. If you want to kill a specific openvpn instance using tun0.

        ```sh
        kill -TERM $(pgrep -f "openvpn.*tun0")
        ```
  
</details>

<details>
  <summary>How do I check port forwarding on the VPN side is working?</summary>
  
  * Use a port checking tool (like https://websistent.com/tools/open-port-check-tool/) and enter your VPN IP and VPN port number to test. Check both IPv6 and IPv4 if using both. 
  * Alternatively, you can run the following command on your client which tells your IP and if the port is open. Make sure you are not seeing your real IP here and that the status for the port is reachable. Replace 21674 with your VPN port number. 
  
    ```sh
     curl -4 https://am.i.mullvad.net/port/21674
     curl -6 https://am.i.mullvad.net/port/21674
     ```
     
</details>

<details>
  <summary>Why I am seeing my real IPv6 address when checking my IP on the Internet?</summary>
  
  * You shouldn't be seeing your real IPv6 address anywhere if you forced your clients over IPv6, even if your VPN doesn't support IPv6. Make sure that you are forcing your client through IPv6 as well as IPv4, by forcing through interface (`FORCED_SOURCE_INTERFACE`), MAC address (`FORCED_SOURCE_MAC`), or the IPv6 directly (`FORCED_SOURCE_IPV6`). 
  
  * If IPv6 is not supported by your VPN provider, IPv6 traffic should time out or be refused. For additional security if your VPN provider doesn't support IPv6, it is recommended to set the `DNS_IPV6_IP` option to "REJECT", or disable IPv6 for that network in the UDMP settings, so that IPv6 DNS leaks do not occur.
     
</details>

<details>
  <summary>Why am I seeing my real IPv6 address when doing a WebRTC test?</summary>
  
  * WebRTC is an audio/video protocol that allows browsers to get your IPs via JavaScript. WebRTC cannot be completely disabled at the network level because some browsers check the network interface directly to see what IP to return. Since IPv6 has global IPs directly assigned to the network interface, your non-VPN global IPv6 can be directly seen by the browser and leaked to WebRTC JavaScript calls. To solve this, you can do one of the following.
  
    * Disable WebRTC on your browser (not all browsers allow you to). Use a browser like Firefox that allows you to disable WebRTC.
    * Disable JavaScript completely on your browser (which will break most sites).
    * Disable IPv6 completely either directly on the client (if you can), or by using the UDMP's network settings to turn off IPv6 for the client's VLAN.
  
</details>

<details>
  <summary>My VPN provider doesn't support IPv6. Why do my forced clients have a delay in communicating to the Internet?</summary>
  
  * If your VPN provider doesn't support IPv6 but you have IPv6 enabled on the network, clients will attempt to communicate over IPv6 first then fallback to IPv4 when the connection fails, since IPv6 is not supported on the VPN. 
  
  * To avoid this delay, it is recommended to disable IPv6 for that network/VLAN in the UDMP settings, or on the client directly. This ensures that the clients only use IPv4 and don't have to wait for IPv6 to time out first.
     
</details>

<details>
  <summary>Does the VPN still work when my IP changes because of lease renewals or other disconnect reasons?</summary>
    
  * Yes, as long as you add the `--ping-restart X` option to the openvpn command line when you run it. This ensures that if there is a network disconnect for any reason, the OpenVPN client will restart and try to re-configure itself after X seconds until it connects again. 
  
  * The killswitch will still be active during the restart to block non-VPN traffic as long as you set `REMOVE_KILLSWITCH_ON_EXIT=0` in the config.
  
</details>

<details>
  <summary>The VPN exited or crashed and now I can't access the Internet on my devices. What do I do?</summary>
  
  * When the VPN process crashes, there is no cleanup done for the iptable rules and the killswitch is still active. This is also the case for a clean exit when you set the option `REMOVE_KILLSWITCH_ON_EXIT=0`. This is a safety feature so that there are no leaks if the VPN crashes. To recover the connection, do either of the following:
  
    * If you don't want to delete the killswitch and leak your real IP, re-run the openvpn run script or command to bring the VPN back up again.

    * If you want to delete the killswitch so your forced clients can access your default network again instead of go through the VPN, run the following command (replace tun0 with the device you defined in the config file) after changing to the directory with the vpn.conf file. 
    
        ```sh
        cd /mnt/data/openvpn/nordvpn
        /mnt/data/openvpn/updown.sh tun0 force-down
        ```
      
</details>

<details>
  <summary>What does this really do to my UDMP?</summary>
  
  * This script only does the following.
  
    1. Adds custom iptable chains and rules to the mangle, nat, and filter tables. You can see them with the following commands (assuming you set `PREFIX=VPN_`).

        ```sh
        iptables -t mangle -S | grep VPN
        iptables -t nat -S | grep VPN
        iptables -t filter -S | grep VPN
        ip6tables -t mangle -S | grep VPN
        ip6tables -t nat -S | grep VPN
        ip6tables -t filter -S | grep VPN
        ```

    2. Adds VPN routes to custom routing tables that can be seen with the following command (assuming you set `ROUTE_TABLE=101`).

        ```sh
        ip route show table 101
        ip -6 route show table 101
        ```

    2. Adds policy-based routes to redirect marked traffic to the custom tables. You can see them with the following command (look for the fwmark you defined in your config or 0x9 if using default).

        ```sh
        ip rule
        ip -6 rule
        ```

    4. Stays running in the background to monitor the policy-based routes every second for any deletions caused by the UDMP operating system, and re-adds them if deleted. The UDMP removes the custom policy-based routes when the WAN IP changes. You can see the script running with:

        ```sh
        ps | grep updown.sh
        ```

    5. Writes logs to `openvpn.log` and `rule-watcher.log` in each VPN server's directory. Logs are overwritten at every run.
      
</details>

<details>
  <summary>Something went wrong. How can I debug?</summary>
  
  1. First check the openvpn.log file in the VPN server's directory for any errors. 
  2. Check that the iptable rules, policy-based routes, and custom table routes agree with your configuration. See the previous question for how to look this up.
  3. If you want to see which line the scripts failed on, open the `updown.sh` and `add-vpn-iptables-rules.sh` scripts and replace the `set -e` line at the top with `set -xe` then rerun the VPN. The `-x` flag tells the shell to print every line before it executes it. 
  4. Post a bug report if you encounter any reproducible issues. 
  
</details>

## Configuration variables

<details>
  <summary>Settings are modified in vpn.conf. Multiple entries can be entered for each setting by separating the entries with spaces. Click here to see all the settings.</summary>
  
  <details>
    <summary>FORCED_SOURCE_INTERFACE</summary>
      Force all traffic coming from a source interface through the VPN. 
      Default LAN is br0, and other LANs are brX, where X = VLAN number.

      Format: [INTERFACE NAME]
      Example: FORCED_SOURCE_INTERFACE="br6 br8"

  </details>
  
  <details>
    <summary>FORCED_SOURCE_IPV4</summary>
      Force all traffic coming from a source IPv4 through the VPN. 
      IP can be entered in CIDR format to cover a whole subnet. 
  
      Format: [IP/nn]
      Example: FORCED_SOURCE_IPV4="192.168.1.1/32 192.168.3.0/24"

  </details>
  
  <details>
    <summary>FORCED_SOURCE_IPV6</summary>
      Force all traffic coming from a source IPv6 through the VPN. 
      IP can be entered in CIDR format to cover a whole subnet. 
  
      Format: [IP/nn]
      Example: FORCED_SOURCE_IPV6="fd00::2/128 2001:1111:2222:3333::/56"

  </details>
  
  <details>
    <summary>FORCED_SOURCE_MAC</summary>
      Force all traffic coming from a source MAC through the VPN.
  
      Format: [MAC]
      Example: FORCED_SOURCE_MAC="00:aa:bb:cc:dd:ee 30:08:d7:aa:bb:cc"

  </details>
  
  <details>
    <summary>EXEMPT_SOURCE_IPV4</summary>
      Exempt IPv4 sources from the VPN. This allows you to create exceptions to the force rules above. For example, if you forced a whole interface with FORCED_SOURCE_INTERFACE, you can selectively choose clients from that VLAN to exclude.
  
      Format: [IP/nn]
      Example: EXEMPT_SOURCE_IPV4="192.168.1.2/32 192.168.3.8/32"

  </details>
  
  <details>
    <summary>EXEMPT_SOURCE_IPV6</summary>
      Exempt IPv6 sources from the VPN. This allows you to create exceptions to the force rules above. 
  
      Format: [IP/nn]
      Example: EXEMPT_SOURCE_IPV6="2001:1111:2222:3333::2 2001:1111:2222:3333::10"

  </details>
  
  <details>
    <summary>EXEMPT_SOURCE_MAC</summary>
      Exempt MAC sources from the VPN. This allows you to create exceptions to the force rules above. 
  
      Format: [MAC]
      Example: EXEMPT_SOURCE_MAC="00:aa:bb:cc:dd:ee 30:08:d7:aa:bb:cc"

  </details>
   
  <details>
    <summary>EXEMPT_SOURCE_IPV4_PORT</summary>
      Exempt an IPv4:Port source from the VPN. This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN. For example, you can tunnel all traffic through the VPN for some client, but have port 22 still be accessible over the LAN/WAN so you can SSH to it normally. 
  
      A single entry can have up to 15 multiple ports by separating the ports with commas. 
      Ranges of ports can be defined with a colon like 5000:6000, and take up two ports in the entry. 
      Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[IP Source]-[port1,port2:port3,port4,...]
      Example: EXEMPT_SOURCE_IPV4_PORT="tcp-192.168.1.1-22,32400,80:90,443 both-192.168.1.3-53"

  </details>
  
  <details>
    <summary>EXEMPT_SOURCE_IPV6_PORT</summary>
      Exempt an IPv6:Port source from the VPN. This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN. 
 
      A single entry can have up to 15 multiple ports by separating the ports with commas. 
      Ranges of ports can be defined with a colon like 5000:6000, and take up two ports in the entry. 
      Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[IP Source]-[port1,port2:port3,port4,...]
      Example: EXEMPT_SOURCE_IPV6_PORT="tcp-fd00::69-22,32400,80:90,443 both-fd00::2-53"

  </details> 
  
  <details>
    <summary>EXEMPT_DESTINATIONS_IPV4</summary>
      Exempt IPv4 destinations from the VPN. For example, you can allow a LAN subnet so VPN-forced clients are still able to communicate with others on that VLAN, or you can exempt a local DNS address if you want to have local DNS to your pihole or DoH client.
  
      Format: [IP/nn]
      Example: EXEMPT_DESTINATIONS_IPV4="192.168.1.0/24 10.0.5.3/32"

  </details>

  <details>
    <summary>EXEMPT_DESTINATIONS_IPV6</summary>
      Exempt IPv6 destinations from the VPN. For example, you can allow a LAN subnet so VPN-forced clients are still able to communicate with others on that VLAN, or you can exempt a local DNS address if you want to have local DNS to your pihole or DoH client.
  
      Format: [IP/nn]
      Example: EXEMPT_DESTINATIONS_IPV6="fd62:1200:1300:1400::2/32 2001:1111:2222:3333::/56"

  </details>
  
  <details>
    <summary>PORT_FORWARDS_IPV4</summary>
      Forward ports on the VPN side to a local IPv4:port. Not all VPN providers support port forwards. The ports are usually given to you on the provider's portal.
  
      Only one port per entry. Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[VPN Port]-[Forward IP]-[Forward Port]
      Example: PORT_FORWARDS_IPV4="tcp-21674-192.168.1.1-50001 tcp-31683-192.168.1.1-22"

  </details>
  
  <details>
    <summary>PORT_FORWARDS_IPV6</summary>
      Forward ports on the VPN side to a local IPv6:port. Not all VPN providers support port forwards. The ports are usually given to you on the provider's portal.
  
      Only one port per entry. Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[VPN Port]-[Forward IP]-[Forward Port]
      Example: PORT_FORWARDS_IPV6="tcp-21674-2001:aaa:bbbb:2acc::69-50001 tcp-31456-2001:aaa:bbbb:2acc::70-443"

  </details>
  
  <details>
    <summary>DNS_IPV4_IP, DNS_IPV4_PORT</summary>
      Redirect DNS IPv4 traffic of VPN-forced clients to this IP and port.
      If set to "DHCP", the DNS will try to be obtained from the DHCP options that the VPN sends. 
      If set to "REJECT", DNS requests over IPv6 will be blocked instead. 
      Note that many VPN providers redirect all DNS traffic to their servers, so redirection to other IPs might not work on all providers.
      DNS redirects to a local address, or rejecting DNS traffic works for all providers.
      Make sure to set DNS_IPV4_INTERFACE if redirecting to a local DNS address. 
  
      Format: [IP] or "DHCP" or "REJECT"
      Example: DNS_IPV4_IP="1.1.1.1"
      Example: DNS_IPV4_IP="DHCP"
      Example: DNS_IPV4_IP="REJECT"
      Example: DNS_IPV4_PORT=53

  </details>
  
  <details>
    <summary>DNS_IPV4_INTERFACE</summary>
      Set this to the interface (brX) the IPv4 DNS is on if it is a local IP. Leave blank for non-local DNS. 
      Local DNS redirects will not work without specifying the interface.
  
      Format: [brX]
      Example: DNS_IPV4_INTERFACE="br0"

  </details>
  
  <details>
    <summary>DNS_IPV6_IP, DNS_IPV6_PORT</summary>
      Redirect DNS IPv6 traffic of VPN-forced clients to this IP and port. 
      If set to "REJECT", DNS requests over IPv6 will be blocked instead. The REJECT option is recommended to be enabled for VPN providers that don't support IPv6, to eliminate any IPv6 DNS leaks.
      Note that many VPN providers redirect all DNS traffic to their servers, so redirection to other IPs might not work on all providers.
      DNS redirects to a local address, or rejecting DNS traffic works for all providers.
      Make sure to set DNS_IPV6_INTERFACE if redirecting to a local DNS address. 
  
      Format: [IP] or "REJECT"
      Example: DNS_IPV6_IP="2606:4700:4700::64"
      Example: DNS_IPV6_IP="REJECT"
      Example: DNS_IPV6_PORT=53

  </details>
  
  <details>
    <summary>DNS_IPV6_INTERFACE</summary>
      Set this to the interface (brX) the IPv6 DNS is on if it is a local IP. Leave blank for non-local DNS. 
      Local DNS redirects will not work without specifying the interface.
  
      Format: [brX]
      Example: DNS_IPV6_INTERFACE="br0"

  </details>
  
  <details>
    <summary>KILLSWITCH</summary>
      Enable killswitch which adds an iptables rule to reject VPN-destined traffic that doesn't go out of the VPN. 
  
      Format: 0 or 1
      Example: KILLSWITCH=1

  </details>
  
  <details>
    <summary>REMOVE_KILLSWITCH_ON_EXIT</summary>
      Remove the killswitch on exit. 
      It is recommended to set this to 0 so that the killswitch is not removed in case the openvpn client crashes, disconnects, or restarts. 
      Setting this to 1 will remove the killswitch when the openvpn client restarts, which means clients might be able to communicate with your default WAN and leak your real IP while the openvpn client is restarting. 
  
      Format: 0 or 1
      Example: REMOVE_KILLSWITCH_ON_EXIT=0

  </details>
  
  <details>
    <summary>REMOVE_STARTUP_BLACKHOLES</summary>
    Enable this if you added blackhole routes in the Unifi Settings to prevent Internet access at system startup before the VPN script runs. 
    This option removes the blackhole routes to restore Internet access after the killswitch has been enabled.               
    If you do not set this to 1, openvpn will not be able to connect at startup, and your Internet access will never be enabled until you manually remove the blackhole routes. 
    Set this to 0 only if you did not add any blackhole routes in Step 6 of the boot script instructions above.                         
  
      Format: 0 or 1
      Example: REMOVE_STARTUP_BLACKHOLES=1

  </details>
  
  <details>
    <summary>ROUTE_TABLE</summary>
      The custom route table number. 
      If you are running multiple openvpn clients, this needs to be unique for each client.
  
      Format: [Number]
      Example: ROUTE_TABLE=101

  </details>
  
  <details>
    <summary>MARK</summary>
      The firewall mark that will be used to mark the packets destined to the VPN. 
      If you are running multiple openvpn clients, this needs to be unique for each client.
  
      Format: [Hex number]
      Example: MARK=0x9

  </details>
  
  <details>
    <summary>PREFIX</summary>
      The prefix that will be used when adding custom iptables chains. 
      If you are running multiple openvpn clients, this needs to be unique for each client. 

      Format: [Prefix]
      Example: PREFIX=VPN_

  </details>
  
  <details>
    <summary>PREF</summary>
      The preference that will be used when adding the policy-based routing rule.
      It should preferably be less than the UDM rules seen when running "ip rule".

      Format: [Number]
      Example: PREF=99

  </details>
  
  <details>
    <summary>DEV</summary>
    The name of the VPN tunnel device to use for openvpn. 
    If you are running multiple openvpn clients, this needs to be unique for each client. 
    This variable needs to be passed to openvpn via the --dev option or openvpn will default to tun0.

      Format: [tunX]
      Example: DEV=tun0

  </details>
  
</details>
