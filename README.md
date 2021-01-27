# split-vpn
A split tunnel VPN script for the UDM/P.

## What is this?

This is a helper script for the OpenVPN client on the UDMP that creates a split tunnel for the VPN connection, and forces configured clients through the VPN instead of the default WAN. This is accomplished by marking every packet of the forced clients with an iptables firewall mark (fwmark), adding the VPN routes to a custom routing table, and using a policy-based routing rule to direct the marked traffic to the custom table. 

## Features

* Force traffic to the VPN based on source interface (VLAN), MAC address, or IP address.
* Exempt sources from the VPN based on IP, MAC address, or IP:port combination. This allows you to force whole VLANs through by interface, but then selectively choose clients from that VLAN, or specific services on forced clients, to exclude from the VPN.
* Exempt destinations from the VPN by IP. This allows VPN-forced clients to communicate with the LAN.
* Port forwarding on the VPN side to local clients (not all VPN providers give you ports).
* Redirect DNS for VPN traffic, or block it for IPv6. 
* Built-in kill switch via iptables and blackhole routing.
* Can be used with multiple openvpn instances with separate configurations for each. This allows you to force different clients through different VPN servers. 
* IPv6 support for all options.

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
4. If your VPN provider uses a username/password, put them in a username_password.txt file in the same directory as the configuration with the username on the first line and password on the second line. Then either: 
    * Edit your VPN provider's openvpn config you downloaded in step 3 to reference the username_password.txt file by adding/changing this directive: `auth-user-pass username_password.txt`.
    * Use the `--auth-user-pass username_password.txt` option when you run openvpn below in step 6 or 8. 
    
    NOTE: The username/password for openvpn are usually given to you in a file or in your VPN provider's online portal. They are usually not the same as your login to the VPN. 
5. Edit the vpn.conf file with your desired settings. See the explanation of each setting [below](#configuration-variables). 
6. Run OpenVPN in the foreground to test if everything is working properly.
```sh
openvpn --config nordvpn.ovpn \
        --route-noexec \
        --up /mnt/data/openvpn/updown.sh \
        --down /mnt/data/openvpn/updown.sh \
        --script-security 2
```
7. If the connection works, check if your forced clients are on the VPN by visiting http://whatismyip.host/ and seeing if your IPs are different than your WAN. Also, check for DNS leaks with the Extended Test on https://www.dnsleaktest.com/.
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
/mnt/data/openvpn/add-vpn-iptables-rules.sh up ${DEV}
nohup openvpn --config nordvpn.ovpn \
              --route-noexec \
              --up /mnt/data/openvpn/updown.sh \
              --down /mnt/data/openvpn/updown.sh \
              --dev-type tun --dev ${DEV} \
              --script-security 2 \
              --ping-restart 15 \
              --mute-replay-warnings > openvpn.log &
```
Remember to modify the `cd` line and the `--config` openvpn option to point to your config. Comment out the `add-vpn-iptables-rules.sh` line if you want the iptables kill switch to not be activated until after the VPN connects.

3. Run `chmod +x /mnt/data/on_boot.d/run-vpn.sh` to give the script execute permissions. 
4. That's it. Now the VPN will start at every boot.
5. Note that there is a short period between when the UDMP starts and when this script runs. This means there is a few seconds when the UDMP starts up when your forced clients **WILL** have access to your WAN, because the kill switch has not been activated yet. After the script runs, forced clients will not be able to access your WAN even if openvpn crashes or restarts (see the option).

</details>

## FAQ
<details>
  <summary>Can I route clients to different VPN servers?</summary>
    Yes you can. Simply make a separate directory for each VPN server, and give them each a vpn.conf file with the clients you wish to force through them. Make sure the options ROUTE_TABLE, MARK, PREFIX, PREF, and DEV are unique for each vpn.conf file so the different VPN servers don't share the same tunnel device or mark. 
   
   Afterwards, modify your run script like so (in this example, we are using Mullvad and NordVPN). Note that you need to cd into the correct directory for each different VPN server before running the openvpn command so that the correct config file is used for each and a unique TUN device is passed to openvpn.

    #!/bin/sh

    # Load configuartion for mullvad and run openvpn
    cd /mnt/data/openvpn/mullvad
    source ./vpn.conf
    /mnt/data/openvpn/add-vpn-iptables-rules.sh up ${DEV}
    nohup openvpn --config mullvad.conf \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --script-security 2 \
                  --dev-type tun --dev ${DEV} \
                  --ping-restart 15 \
                  --mute-replay-warnings > openvpn.log &

    # Load configuartion for nordvpn and run openvpn
    cd /mnt/data/openvpn/nordvpn
    source ./vpn.conf
    /mnt/data/openvpn/add-vpn-iptables-rules.sh up ${DEV}
    nohup openvpn --config nordvpn.ovpn \
                  --route-noexec \
                  --up /mnt/data/openvpn/updown.sh \
                  --down /mnt/data/openvpn/updown.sh \
                  --script-security 2 \
                  --dev-type tun --dev ${DEV} \
                  --ping-restart 15 \
                  --mute-replay-warnings > openvpn.log &

</details>

<details>
  <summary>How do I safely shutdown the VPN?</summary>
  Simply send the openvpn process the TERM signal. Killswitch and iptables rules will only be removed if the option REMOVE_KILLSWITCH_ON_EXIT is set to 1.
  
  1. If you want to kill all openvpn instances.
    
    killall -TERM openvpn
  
  2. If you want to kill a specific openvpn instance using tun0.
    
    kill -TERM $(pgrep -f "openvpn.*tun0")
  
</details>

<details>
  <summary>Does the VPN still work when my IP changes because of lease renewals or other disconnect reasons?</summary>
    Yes, as long as you add the "--ping-restart X" option to the openvpn command line when you run it. This ensures that if there is a network disconnect for any reason, the OpenVPN client will restart and try to re-configure itself after X seconds until it connects again. The killswitch will still be active during the restart to block non-VPN traffic as long as you set REMOVE_KILLSWITCH_ON_EXIT=0 in the config.
  
</details>

<details>
  <summary>The VPN exited or crashed and now I can't access the Internet on my devices. What do I do?</summary>
  When the VPN process crashes, there is no cleanup done for the iptable rules and the killswitch is still active. This is also the case for a clean exit when you set the option REMOVE_KILLSWITCH_ON_EXIT=0. This is a safety feature so that there are no leaks if the VPN crashes.
  
  1. If you don't want to delete the killswitch and leak your real IP, re-run the openvpn run script or command to bring the VPN back up again.

  2. If you want to delete the killswitch so your forced clients can access your default network again instead of go through the VPN, run the following command (replace tun0 with the device you defined in the config file) after changing to the directory with the vpn.conf file. 
    
    cd /mnt/data/openvpn/nordvpn
    /mnt/data/openvpn/updown.sh tun0 force-down
      
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
  
      A single entry can have multiple ports by seperating the ports with commas. Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[IP Source]-[port1,port2,...]
      Example: EXEMPT_SOURCE_IPV4_PORT="tcp-192.168.1.1-22,32400,80,443 both-192.168.1.3-53"

  </details>
  
  <details>
    <summary>EXEMPT_SOURCE_IPV6_PORT</summary>
      Exempt an IPv6:Port source from the VPN. This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN. 
  
      A single entry can have multiple ports by seperating the ports with commas. Protocal can be tcp, udp or both. 
      Format: [tcp/udp/both]-[IP Source]-[port1,port2,...]
      Example: EXEMPT_SOURCE_IPV6_PORT="tcp-fd00::69-22,32400,80,443 both-fd00::2-53"

  </details> 
  
  <details>
    <summary>EXEMPT_DESTINATIONS_IPV4</summary>
      Exempt IPv4 destinations from the VPN. For example, you can allow a LAN subnet so VPN-forced clients are still able to communicate with others on the LAN, or you can exempt a local DNS address if you want to have local DNS to your pihole or DoH client.
  
      Format: [IP/nn]
      Example: EXEMPT_DESTINATIONS_IPV4="192.168.1.0/24 10.0.5.3/32"

  </details>

  <details>
    <summary>EXEMPT_DESTINATIONS_IPV6</summary>
      Exempt IPv6 destinations from the VPN.  
  
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
      Note that many VPN providers redirect all DNS traffic to their servers, so this rule woudldn't make a difference.
  
      Format: [IP] or "DHCP"
      Example: DNS_IPV4_IP="1.1.1.1"
      Example: DNS_IPV4_IP="DHCP"
      Example: DNS_IPV4_PORT="53"

  </details>
  
  <details>
    <summary>DNS_IPV6_IP, DNS_IPV6_PORT</summary>
      Redirect DNS IPv6 traffic of VPN-forced clients to this IP and port. 
      If set to "REJECT", the DNS requests over IPv6 will be blocked instead. The REJECT option is recommended to be enabled for VPN providers that don't support IPv6, to eliminate any IPv6 DNS leaks.
  
      Format: [IP] or "REJECT"
      Example: DNS_IPV6_IP="2606:4700:4700::64"
      Example: DNS_IPV6_IP="REJECT"
      Example: DNS_IPV6_PORT="53"

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
      Setting this to 1 will remove the killswitch when the openvpn client restarts, which means clients might be able to communicate with your default WAN while the client is restarting. 
  
      Format: 0 or 1
      Example: REMOVE_KILLSWITCH_ON_EXIT=0

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
