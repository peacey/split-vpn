# split-vpn
A split tunnel VPN script for Unifi OS routers with policy based routing.

## What is this?

This is a helper script for multiple VPN clients on Unifi routers that creates a split tunnel for the VPN connection, and forces configured clients through the VPN instead of the default WAN. This is accomplished by marking every packet of the forced clients with an iptables firewall mark (fwmark), adding the VPN routes to a custom routing table, and using a policy-based routing rule to direct the marked traffic to the custom table. This script works with OpenVPN, WireGuard, OpenConnect, StrongSwan, or an external nexthop VPN client on your network.

## Features

* Works with UDM-Pro, UDM, UDM-SE, UDR, and UXG-Pro.
* Force traffic to the VPN based on source interface (VLAN), MAC address, IP address, or IP sets.
* Exempt sources from the VPN based on IP, MAC address, IP:port, MAC:port combinations, or IP sets. This allows you to force whole VLANs through by interface, but then selectively choose clients from that VLAN, or specific services on forced clients, to exclude from the VPN.
* Exempt destinations from the VPN by IP. This allows VPN-forced clients to communicate with the LAN or other VLANs.
* Force domains to the VPN or exempt them from the VPN (only supported with dnsmasq or pihole).
* Port forwarding on the VPN side to local clients (not all VPN providers give you ports).
* Redirect DNS for VPN traffic to either an upstream DNS server or a local server like pihole, or block DNS requests completely.
* Built-in kill switch via iptables and blackhole routing.
* Works across IP changes, network restarts, and the Unifi OS' WAN Failover.
* Can be used with multiple openvpn instances with separate configurations for each. This allows you to force different clients through different VPN servers.
* IPv6 support for all options.
* Run on boot support via UDM-Utilities boot script or systemd.
* Supports OpenVPN, WireGuard kernel module, wireguard-go docker container, OpenConnect docker container (AnyConnect), StrongSwan docker container (IKEv2 and IPSec), and external VPN clients on your network (nexthop).

## Compatibility

This script is designed to be run on the UDM-Pro, UDM, UDM-SE, UDR, or UXG-Pro. It has been tested on Unifi OS 1.8 to 1.12, and 2.2 to 2.4, however other versions should work. Please submit a bug report if you use this on a different version and encounter issues.

## Installation Instructions

1. SSH into the Unifi router (assuming it's on 192.168.1.254).

    ```sh
    ssh root@192.168.1.254
    ```

2. Download and run the installation script.

    ```sh
    curl -LSsf https://raw.githubusercontent.com/peacey/split-vpn/main/vpn/install-split-vpn.sh | sh
    ```

	* If using UnifiOS 1.x, this script will be installed to `/mnt/data/split-vpn`.
	* If using UnifiOS 2.x/3.x, this script will be installed to `/data/split-vpn`.
	* The installation will also link the script directory to `/etc/split-vpn`, which will be used for configuration below.

3. Follow the instructions below to set-up the script.

## How do I use this?

* Make sure you first installed split-vpn with the instructions outlined above.
* Make sure split-vpn is linked to `/etc/split-vpn` before proceeding. This is done automatically at install, but needs to be done every reboot. Boot scripts included below automatically set up this link at boot.
	* If you are not using a boot script, you can re-create the link by running `/mnt/data/split-vpn/vpn/setup-split-vpn.sh` if using UnifiOS 1.x or `/data/split-vpn/vpn/setup-split-vpn.sh` if using UnifiOS 2.x.

<details>
  <summary>Click here to see the instructions for OpenVPN.</summary>

1. Create a directory for your VPN provider's openvpn configuration files, and copy your VPN's configuration files (certificates, config, password files, etc) and the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`. NordVPN is used below as an example.

    ```sh
    mkdir -p /etc/split-vpn/openvpn/nordvpn
    cd /etc/split-vpn/openvpn/nordvpn
    curl https://downloads.nordcdn.com/configs/files/ovpn_legacy/servers/us-ca40.nordvpn.com.udp1194.ovpn --out nordvpn.ovpn
    cp /etc/split-vpn/vpn/vpn.conf.sample /etc/split-vpn/openvpn/nordvpn/vpn.conf
    ```

2. If your VPN provider uses a username/password, put them in a `username_password.txt` file in the same directory as the configuration with the username on the first line and password on the second line. Then either:
    * Edit your VPN provider's openvpn config you downloaded in step 3 to reference the username_password.txt file by adding/changing this directive: `auth-user-pass username_password.txt`.
    * Use the `--auth-user-pass username_password.txt` option when you run openvpn below in step 6 or 8.

    NOTE: The username/password for openvpn are usually given to you in a file or in your VPN provider's online portal. They are usually not the same as your login to the VPN.
3. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables).
    * At minimum, set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
4. Run OpenVPN in the foreground to test if everything is working properly.

    ```sh
    openvpn --config nordvpn.ovpn \
            --route-noexec --redirect-gateway def1 \
            --up /etc/split-vpn/vpn/updown.sh \
            --down /etc/split-vpn/vpn/updown.sh \
            --script-security 2
    ```

5. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

6. If everything is working properly, stop the OpenVPN client by pressing Ctrl+C. Then, create a run script to run it in the background by creating a new file under the current directory called `run-vpn.sh`.

      ```sh
      #!/bin/sh
      # Load configuration and run openvpn
      cd /etc/split-vpn/openvpn/nordvpn
      . ./vpn.conf
      # /etc/split-vpn/vpn/updown.sh ${DEV} pre-up >pre-up.log 2>&1
      nohup openvpn --config nordvpn.ovpn \
                    --route-noexec --redirect-gateway def1 \
                    --up /etc/split-vpn/vpn/updown.sh \
                    --down /etc/split-vpn/vpn/updown.sh \
                    --dev-type tun --dev ${DEV} \
                    --script-security 2 \
                    --ping-restart 15 \
                    --mute-replay-warnings >openvpn.log 2>&1 &
      ```

    * Modify the `cd` line to point to the correct directory and the `--config` option to point to the right OpenVPN configuration file.
    * You can modify the command to change `--ping-restart` or other options as needed. The only requirement is that you run updown.sh script as the up/down script and `--route-noexec` to disable OpenVPN from adding routes to the default table instead of our custom one. In some cases, `--redirect-gateway def1` is needed to set the correct VPN gateway.
    * **Optional**: If you want to enable the killswitch to block Internet access to forced clients if OpenVPN crashes, set `KILLSWITCH=1` in the `vpn.conf` file before starting OpenVPN. If you also want to block Internet access to forced clients when you exit OpenVPN cleanly (with SIGTERM), then set `REMOVE_KILLSWITCH_ON_EXIT=0`.
    * **Optional**: Uncomment the pre-up line by removing the `# ` at the beginning of the line if you want to block Internet access for forced clients while the VPN is in the process of connecting. Keeping it commented out doesn't enable the iptables kill switch until after OpenVPN connects.

7. Give the run script executable permissions and run it once.

    ```sh
    chmod +x /etc/split-vpn/openvpn/nordvpn/run-vpn.sh
    /etc/split-vpn/openvpn/nordvpn/run-vpn.sh
    ```

    * If you need to bring down the VPN tunnel and rules, run `killall -TERM openvpn` to bring down all OpenVPN clients, or `kill -TERM $(pgrep -f "openvpn.*tun0")` to bring down the OpenVPN using tun0.

8. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.
9. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

</details>

<details>
  <summary>Click here to see the instructions for WireGuard (kernel module).</summary>

  * **PREREQUISITE:** This method requires the WireGuard kernel module and tools. The module and tools are included by Uiquiti in UnifiOS 2.x and up, but for UnifiOS 1.x, you will have to install the module and tools first via either the [wireguard-kmod](https://github.com/tusc/wireguard-kmod) project or a [custom kernel](https://github.com/fabianishere/udm-kernel-tools).
  * If using wireguard-kmod, make sure you run the wireguard setup script from [wireguard-kmod](https://github.com/tusc/wireguard-kmod) once before starting these instructions.
  * Before continuing, test the installation of the module by running `modprobe wireguard` which should return nothing and no errors, and running `wg-quick` which should return the help and no errors.
	
1. Create a directory for your WireGuard configuration files, copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`, and copy your WireGuard configuration file (wg0.conf) or create it. As an example below, we are creating the wg0.conf file that mullvad provides and pasting the contents into it. You can use any name for your config instead of wg0 (e.g.: mullvad-ca2.conf) and this will be the interface name of the wireguard tunnel.

    ```sh
    mkdir -p /etc/split-vpn/wireguard/mullvad
    cd /etc/split-vpn/wireguard/mullvad
    cp /etc/split-vpn/vpn/vpn.conf.sample /etc/split-vpn/wireguard/mullvad/vpn.conf
    vim wg0.conf
    ```

    * Press `i` to start editing in vim, right click -> paste, press `ESC` to exit insert mode, type `:wq` to save and exit.

2. In your WireGuard config (wg0.conf), set PostUp and PreDown to point to the updown.sh script, and Table to a custom route table number that you will use in this script's vpn.conf. Here is an example wg0.conf file:

    ```
    [Interface]
    PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    Address = 10.68.1.88/32,fc00:dddd:eeee:bb01::5:6666/128
    PreUp = CONFIG_FILE=/etc/split-vpn/vpn/vpn.conf sh /etc/split-vpn/vpn/updown.sh %i pre-up
    PostUp = CONFIG_FILE=/etc/split-vpn/vpn/vpn.conf sh /etc/split-vpn/vpn/updown.sh %i up
    PreDown = CONFIG_FILE=/etc/split-vpn/vpn/vpn.conf sh /etc/split-vpn/vpn/updown.sh %i down
    Table = 101

    [Peer]
    PublicKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
    AllowedIPs = 0.0.0.0/1,128.0.0.0/1,::/1,8000::/1
    Endpoint = [2607:f7a0:d:4::a02f]:51820
    ```

    In the above config, make sure to:
      * Comment out or remove the `DNS` line. Use the DNS settings in your `vpn.conf` file instead if you want to force your clients to use a certain DNS server.
      * Set AllowedIPs to `0.0.0.0/1,128.0.0.0/1,::/1,8000::/1` to allow all IPv4 and IPv6 traffic through the VPN. Do not use `0.0.0.0/0,::/0` because it will interfere with the blackhole routes and won't allow wireguard to start. If you prefer to use `0.0.0.0/0,::/0`, disable blackhole routes by setting `DISABLE_BLACKHOLE=1` in your `vpn.conf` file so wireguard can start successfully.
      * Remove any extra PreUp/PostUp/PreDown/PostDown lines that could interfere with the VPN script.
      * You can remove or comment out the PreUp line if you do not want VPN-forced clients to lose Internet access if WireGuard does not start correctly.

3. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure that:
   * You set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
   * The option `DNS_IPV4_IP` and/or `DNS_IPV6_IP` is set to the DNS server you want to force for your clients, or set them to empty if you do not want to force any DNS.
   * The option `VPN_PROVIDER` is set to "external".
   * The option `ROUTE_TABLE` is the same number as `Table` in your `wg0.conf` file.
   * The option `DEV` is set to "wg0" or your interface's name if different (i.e.: the name of your .conf file).

4. Run wg-quick to start wireguard with your configuration and test if the connection worked. Replace wg0 with your interface name if different.

    ```sh
    wg-quick up ./wg0.conf
    ```

    * If you are on using the wireguard-kmod project, make sure you ran the wireguard setup script first (`/mnt/data/wireguard/setup_wireguard.sh` or `/data/wireguard/setup_wireguard.sh`) as instructed at [wireguard-kmod](https://github.com/tusc/wireguard-kmod).
    * Type `wg` to check your WireGuard connection and make sure you received a handshake. No handshake indicates something is wrong with your wireguard configuration. Double check your configuration's Private and Public key and other variables.
    * If you need to bring down the WireGuard tunnel, run `wg-quick down ./wg0.conf` in this folder (replace wg0.conf with your interface configuration if different).
    * Note that wg-quick up/down commands need to be run from this folder so the script can pick up the correct configuration file.

5. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

6. If everything is working, create a run script called `run-vpn.sh` in the current directory so you can easily run this wireguard configuration. Fill the script with the following contents:

    ```sh
    #!/bin/sh

    # Load configuration and run wireguard
    cd /etc/split-vpn/wireguard/mullvad
    . ./vpn.conf
    # /etc/split-vpn/vpn/updown.sh ${DEV} pre-up >pre-up.log 2>&1
    wg-quick up ./${DEV}.conf >wireguard.log 2>&1
    cat wireguard.log
    ```

	* If you are using the wireguard-kmod project, add `/mnt/data/wireguard/setup_wireguard.sh` or `/data/wireguard/setup_wireguard.sh` (whichever your data directory is) to the top of this script before the "# Load configuration" line to make sure wireguard is setup first.
  	* Modify the `cd` line to point to the correct directory. Make sure that the `DEV` variable in the `vpn.conf` file is set to the wireguard interface name (which should the same as the wireguard configuration filename without .conf).
  	* **Optional**: If you want to block Internet access to forced clients if the wireguard tunnel is brought down via wg-quick, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.
  	* **Optional**: Uncomment the pre-up line by removing the `# ` at the beginning of the line if you want to block Internet access for forced clients if wireguard fails to run. Keeping it commented out doesn't enable the iptables kill switch until after wireguard runs successfully.

7. Give the script executable permissions. You can run this script next time you want to start this wireguard configuration.

    ```sh
    chmod +x /etc/split-vpn/wireguard/mullvad/run-vpn.sh
    ```

8. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

9. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

10. Note that the WireGuard protocol is practically stateless, so there is no way to know whether the connection stopped working except by checking that you didn't receive a handshake within 3 minutes or some higher interval. This means if you want to automatically bring down the split-vpn rules when WireGuard stops working and bring it back up when it starts working again, you need to write an external script to check the last handshake condition every few seconds and act on it (not covered here).

</details>

<details>
  <summary>Click here to see the instructions for wireguard-go (software implementation).</summary>

  * **PREREQUISITE:** Make sure the wireguard-go container is installed as instructed at the [wireguard-go repo](https://github.com/boostchicken/udm-utilities/tree/master/wireguard-go). After this step, you should have the wireguard directory (for example: `/mnt/data/wireguard`) and the run script `/mnt/data/on_boot.d/20-wireguard.sh` installed.
    *   **NOTE:** This requires podman which comes pre-installed on UnifiOS 1.x. For UnifiOS 2.x and up, you need to install podman first (instructions not included).
  * The wireguard-go container only supports a single interface - wg0. This means you cannot connect to multiple wireguard servers. If you want to use multiple servers with this script, then use the WireGuard kernel module instead as explained above.
  * wireguard-go is a software implementation of WireGuard, and will have reduced performance compared to the kernel module.

1. Create a directory for your WireGuard configuration files under `/mnt/data/wireguard` if not created already, copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`, and copy your WireGuard configuration file (wg0.conf) or create it. As an example below, we are creating the wg0.conf file that mullvad provides and pasting the contents into it. You can only use wg0.conf and not any other name because the wireguard-go container expects this configuration file.

    ```sh
    mkdir -p /mnt/data/wireguard
    cd /mnt/data/wireguard
    cp /etc/split-vpn/vpn/vpn.conf.sample /mnt/data/wireguard/vpn.conf
    vim wg0.conf
    ```

    * Press `i` to start editing, right click -> paste, press `ESC` to exit insert mode, type `:wq` to save and exit.


2. In your WireGuard config (wg0.conf), set Table to a custom route table number that you will use in this script's vpn.conf. Here is an example wg0.conf file:

    ```
    [Interface]
    PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    Address = 10.68.1.88/32,fc00:dddd:eeee:bb01::5:6666/128
    Table = 101

    [Peer]
    PublicKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
    AllowedIPs = 0.0.0.0/1,128.0.0.0/1,::/1,8000::/1
    Endpoint = [2607:f7a0:d:4::a02f]:51820
    ```

    In the above config, make sure to:
      * Comment out or remove the `DNS` line. Use the DNS settings in your `vpn.conf` file instead if you want to force your clients to use a certain DNS server.
      * Set AllowedIPs to `0.0.0.0/1,128.0.0.0/1,::/1,8000::/1` to allow all IPv4 and IPv6 traffic through the VPN. Do not use `0.0.0.0/0,::/0` because it will interfere with the blackhole routes and won't allow wireguard to start. If you prefer to use `0.0.0.0/0,::/0`, disable blackhole routes by setting `DISABLE_BLACKHOLE=1` in your `vpn.conf` file so wireguard can start successfully.
      * Remove any extra PreUp/PostUp/PreDown/PostDown lines that could interfere with the VPN script.
      * Do not use PreUp/PostUp/PreDown to call the split-vpn script (like in the wireguard kernel module case) because the container will not have access to the location of the script. Instead, we will call the script manually after bringing the interface up/down as instructed below.

3. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure that:
   * You set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
   * The option `DNS_IPV4_IP` and/or `DNS_IPV6_IP` is set to the DNS server you want to force for your clients, or set them to empty if you do not want to force any DNS.
   * The option `VPN_PROVIDER` is set to "external".
   * The option `ROUTE_TABLE` is the same number as `Table` in your `wg0.conf` file.
   * The option `DEV` is set to "wg0".

4. Create a run script called `run-vpn.sh` in this current directory and fill it with the following:

    ```sh
    #!/bin/sh
    CONTAINER=wireguard

    # Change to the directory with the wireguard configuration.
    cd /mnt/data/wireguard

    # Start the split-vpn pre-up hook.
    # /etc/split-vpn/vpn/updown.sh wg0 pre-up >pre-up.log 2>&1

    # Starts a wireguard container that is deleted after it is stopped.
    # All configs stored in /mnt/data/wireguard
    if podman container exists ${CONTAINER}; then
      podman start ${CONTAINER}
    else
      podman run -i -d --rm --net=host --name ${CONTAINER} --privileged \
        -v /mnt/data/wireguard:/etc/wireguard \
        -v /dev/net/tun:/dev/net/tun \
        -e LOG_LEVEL=info -e WG_COLOR_MODE=always \
        masipcat/wireguard-go:latest-arm64v8
    fi

    # Run the split-vpn up hook if wireguard starts successfully within 5 seconds.
    started=0
    for i in $(seq 1 5); do
            podman exec -it wireguard test -S "/var/run/wireguard/wg0.sock" >/dev/null 2>&1
            if [ $? = 0 ]; then
                    started=1
                    break
            fi
            sleep 1
    done
    if [ $started = 1 ]; then
            echo "wireguard-go started successfully." > wireguard.log
            /etc/split-vpn/vpn/updown.sh wg0 up >> wireguard.log 2>&1
    else
            echo "Error: wireguard-go did not start up correctly within 5 seconds." > wireguard.log
    fi
    cat wireguard.log
    ```

    * The above script will wait up to 5 seconds for the wireguard-go container to start before running the split-vpn up hook to set up the split-vpn rules. The split-vpn up hook will not be run if wireguard-go did not start up correctly.
    * Make sure to delete the old run script (`/mnt/data/on_boot.d/20-wireguard.sh`) if you installed it previously with wireguard-go.
    * **Optional**: If you want to block Internet access to forced clients if the wireguard tunnel is brought down via wg-quick, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.
    * **Optional**: Uncomment the pre-up line by removing the `# ` at the beginning of the line if you want to block Internet access for forced clients if wireguard fails to run. Keeping it commented out doesn't enable the iptables kill switch until after wireguard runs successfully.

5. Give the run script executable permissions and run the run script.

    ```sh
    chmod +x /mnt/data/wireguard/run-vpn.sh
    /mnt/data/wireguard/run-vpn.sh
    ```

6. If wireguard-go started successfully, check that the connection worked by seeing if you received a handshake with the following command:

    ```sh
    podman exec -it wireguard wg
    ```

    * No handshake in the above output indicates something is wrong with your wireguard configuration. Double check your configuration's Private and Public key and other variables.
    * If you need to bring down the WireGuard tunnel and resume normal Internet access to your forced clients, run the following commands in this folder:

      ```sh
      cd /mnt/data/wireguard
      podman stop wireguard
      /etc/split-vpn/vpn/updown.sh wg0 down
      ```

    * Note that split-vpn up/down commands need to be run from this folder so that split-vpn can pick up the correct configuration file.

7. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

8. If you want to continue blocking Internet access to forced clients after the wireguard tunnel is brought down via the split-vpn down command, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.

9. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

10. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

11. Note that the WireGuard protocol is practically stateless, so there is no way to know whether the connection stopped working except by checking that you didn't receive a handshake within 3 minutes or some higher interval. This means if you want to automatically bring down the split-vpn rules when WireGuard stops working and bring it back up when it starts working again, you need to write an external script to check the last handshake condition every few seconds and act on it (not covered here).

</details>

<details>
  <summary>Click here to see the instructions for OpenConnect (i.e. AnyConnect).</summary>

  **NOTE:** This requires podman which comes pre-installed on UnifiOS 1.x. For UnifiOS 2.x and up, you need to install podman first (instructions not included).

1. Create a directory for your OpenConnect configuration files under `/etc/split-vpn/openconnect`, copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`, and copy any certificates needed or other client files for your configuration. As an example below, we are going to connect a server that only uses a username/password, so no certificate is needed, but we have to create a password.txt file and put the password inside it.

    ```sh
    mkdir -p /etc/split-vpn/openconnect/server1
    cd /etc/split-vpn/openconnect/server1
    cp /etc/split-vpn/vpn/vpn.conf.sample vpn.conf
    echo "mypassword" > password.txt
    ```

2. Edit the `vpn.conf` file in this folder with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure that:
    * You set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
    * The options `DNS_IPV4_IP` and `DNS_IPV6_IP` are set to "DHCP" if you want to force VPN-forced clients to use the DNS provided by the VPN server.
    * The option `VPN_PROVIDER` is set to "openconnect". This is required for the script to work with OpenConnect.

3. In the current folder, create a run script that will run the OpenConnect container called `run-vpn.sh`, and fill it with the following code:

    * Tip: Run the vim text editor using `vim run-vpn.sh`, press `i` to enter insert mode, right click on vim -> paste, press `ESC` to exit insert mode, type `:wq` to save and exit.

    ```sh
    #!/bin/sh
    cd "/etc/split-vpn/openconnect/server1"
    . ./vpn.conf
    podman rm -f openconnect-${DEV} >/dev/null 2>&1
    /etc/split-vpn/vpn/updown.sh ${DEV} pre-up
    podman run -id --privileged  --name=openconnect-${DEV} \
        --network host --pid=host \
        -e TZ="$(cat /etc/timezone)" \
        -v "${PWD}:/etc/split-vpn/config" \
        -v "/etc/split-vpn/vpn:/etc/split-vpn/vpn" \
        -w "/etc/split-vpn/config" \
        --restart on-failure \
        peacey/udm-openconnect \
        bash -c "openconnect -s /etc/split-vpn/vpn/vpnc-script -i ${DEV} --reconnect-timeout 1 -u myusername --passwd-on-stdin vpn.server1.com < password.txt &> openconnect.log"
    ```

    * Make sure the 2nd line points to the correct directory with your vpn configuration files.
    * You can modify the options to openconnect in the last line for other authentication types (like certificates). See the OpenConnect authentication options [here](https://www.infradead.org/openconnect/connecting.html). These parameters are for a server that uses a username/password to login.
    * Make sure you change "myusername" in the last line to your username, and "vpn.server1.com" to your VPN server's domain or IP. Make sure you also created the password.txt file with your password.
    * The `--restart on-failure` will make podman try to restart the VPN connection if OpenConnect exits because of a connection error. You can also modify the reconnect timeout via the `--reconnect-timeout 1` option to openconnect in the last line.
    * If you do not want to run the VPN in the background (e.g. for testing), remove the "d" from `podman run -id` in the 5th line.
    * This code writes the output to openconnect.log in the current folder.

4. Give the script executable permissions.

  ```sh
  chmod +x run-vpn.sh
  ```

5. Run the script from the configuration folder.

  ```sh
  ./run-vpn.sh
  ```

  * If you need to bring down the tunnel to restore Internet access to forced clients, run:

    ```sh
    killall -TERM openconnect
    podman rm -f openconnect-tun0
    ````
    * Replace tun0 in the last line with the DEV you configured in vpn.conf (default is tun0). You can also use `kill -TERM $(pgrep -f "openconnect.*tun0")` to kill only the tun0 openconnect instance if you have multiple servers connected.

6. The first time the script runs, it will download the OpenConnect docker container. If the container ran successfully, you should see a random string of numbers and letters. Warnings about major/minor number can be ignored.

    * If the script ran successfully, check the `openconnect.log` file by running `cat openconnect.log`. If the connection is working, you should see that OpenConnect established a connection without errors and that split-vpn ran.

7. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

8. If you want to continue blocking Internet access to forced clients after the openconnect client is shut down, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.

9. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

10. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

</details>

<details>
  <summary>Click here to see the instructions for StrongSwan (IKEv2, IPSec).</summary>

  **NOTE:** This requires podman which comes pre-installed on UnifiOS 1.x. For UnifiOS 2.x and up, you need to install podman first (instructions not included).

1. Create a directory for your StrongSwan configuration files under `/etc/split-vpn/strongswan`, copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`. In this example, we are making a folder for PureVPN.

    ```sh
    mkdir -p /etc/split-vpn/strongswan/purevpn
    cd /etc/split-vpn/strongswan/purevpn
    cp /etc/split-vpn/vpn/vpn.conf.sample vpn.conf
    ```

2. Copy your strongswan configuration that defines your VPN connection and any certificates needed to this folder. In this example, we are downloading the files needed for PureVPN, but the configuration will be different for other VPN providers.

    ```sh
    curl -Lo purevpn.conf https://raw.githubusercontent.com/peacey/split-vpn/main/examples/strongswan/purevpn/purevpn.conf
    curl -Lo USERTrustRSACertificationAuthority.crt https://raw.githubusercontent.com/peacey/split-vpn/main/examples/strongswan/purevpn/USERTrustRSACertificationAuthority.crt
    ```

3. Edit the purevpn.conf strongswan configuration with vim:

    ```sh
    vim purevpn.conf
    ```

    * Tip: Press `i` to enter insert mode, edit the file and make your changes, press `ESC` to exit insert mode, then type `:wq` to save and exit.
    * Change `remote_addrs` variable to your desired PureVPN IKEv2 server.
    * Make sure the folders referenced in `updown` variable are the correct folders. Your configuration needs the updown variable to call the split-vpn script, or the VPN rules will not be installed.
    * Change the 4 instances of `purevpn0dXXXXXXXX` in the file to your own PureVPN username. Make sure to change all 4.
    * Change `secret = "mysecret"` at the bottom of the file to your own password. The password is found in the PureVPN account page, this is not the same password that you use to login to PureVPN's web portal.

4. Edit the `vpn.conf` file in this folder with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure to check:
    * You set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
    * The options `DNS_IPV4_IP` and `DNS_IPV6_IP` are commented out if you want to force VPN-forced clients to use the DNS provided by the VPN server, or set them to set to "" (empty) to disable DNS forcing.
    * The option `VPN_PROVIDER` is set to "external". This is required for the script to work with StrongSwan.
    * Comment out the options `VPN_ENDPOINT_IPV4` and `VPN_ENDPOINT_IPV6` (i.e. add a `#` in front of them).
    * The tunnel device option `DEV` is set to a unique name for each configuration, such as vti256. Ubiquiti uses vti64 and up so do not use anything close to that.

5. In the current folder, create a run script that will run the the StrongSwan container called `run-vpn.sh`, and fill it with the following code:

    ```sh
    #!/bin/sh
    cd "/etc/split-vpn/strongswan/purevpn"
    . ./vpn.conf

    podman rm -f strongswan-${DEV} &> /dev/null
    #/etc/split-vpn/vpn/updown.sh ${DEV} pre-up
    podman run -d --name strongswan-${DEV} --network host --privileged \
        -v "./purevpn.conf:/etc/swanctl/conf.d/purevpn.conf" \
        -v "${PWD}:${PWD}" \
        -v "/etc/split-vpn/vpn:/etc/split-vpn/vpn" \
        -e TZ="$(cat /etc/timezone)" \
        -v "/etc/timezone:/etc/timezone" \
        peacey/udm-strongswan

    # Make sure VPN disconnects before reboot
    initfile="/etc/init.d/S99999stopvpn"
    if [ ! -f "$initfile" ]; then
        echo "#!/bin/sh" > "$initfile"
        chmod +x "$initfile"
    fi
    grep -q "strongswan-${DEV};" "$initfile"
    if [ $? -ne 0 ]; then
        echo 'if [ "$1" = "stop" ]; then podman rm -f strongswan-'"${DEV}"'; fi' >> "$initfile"
    fi
    ```

    * Tip: Run the vim text editor using `vim run-vpn.sh`, press `i` to enter insert mode, right click on vim -> paste, press `ESC` to exit insert mode, type `:wq` to save and exit.
    * Make sure the 2nd line points to the correct directory with your vpn configuration files.
    * Replace the two instances of `purevpn.conf` with your configuration name if different.
    * **Optional**: Uncomment the pre-up line by removing the hash (`#`) at the beginning of the line if you want to block Internet access for forced clients while the VPN is in the process of connecting. Keeping it commented out doesn't enable the iptables kill switch until after the VPN connects.


6. Give the script executable permissions and run it.

      ```sh
      chmod +x run-vpn.sh
      ./run-vpn.sh
      ```

      * If you need to bring down the tunnel to restore Internet access to forced clients, run:

        ```sh
        podman rm -f strongswan-vti256
        ```
        * Replace vti256 in the last line with the DEV you configured in vpn.conf.

7. The first time the script runs, it will download the StrongSwan docker container. If the container ran successfully, you should see a random string of numbers and letters. Warnings about major/minor number can be ignored.

    * If the script ran successfully, check that the VPN tunnel device was created by running `ip addr show dev vti256`, and check that you can ping through the tunnel by running `ping -I vti256 1.1.1.1` (for example).
    * If you're having problems, check the log by running `podman logs strongswan-vti256` (replace vti256 with your DEV if different). Also check `splitvpn-up.log` in the current folder.
    * If you are having intermittent connection issues or websites stalling, you might need to adjust your MSS clamping using the `MSS_CLAMPING_IPV4` or `MSS_CLAMPING_IPV6` options in your `vpn.conf` file.

8. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

9. If you want to continue blocking Internet access to forced clients after the strongswan client is shut down, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.

10. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

11. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

</details>

<details>
  <summary>Click here to see the instructions for an external VPN client setup on another computer on your network (nexthop).</summary>

  * **PREREQUISITE:** Make sure your computer is connected to the VPN and is setup to forward IPv4 and IPv6 packets. You also need to setup a masquerade/SNAT rule on the VPN tunnel interface to make forwarded traffic work properly on the Internet.
    * On a Linux system, the following commands run as root set up IP forwarding and masquerade rules (assuming tun0 is your VPN tunnel interface). These commands have to be run on the VPN computer, not the router.

      ```sh
      sysctl -w net.ipv4.ip_forward=1
      sysctl -w net.ipv6.conf.all.forwarding=1
      sysctl -w net.ipv6.conf.default.forwarding=1
      iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
      ip6tables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
      ```

1. Create a directory for your VPN configuration, and copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`.

    ```sh
    mkdir -p /etc/split-vpn/nexthop/mycomputer
    cd /etc/split-vpn/nexthop/mycomputer
    cp /etc/split-vpn/vpn/vpn.conf.sample vpn.conf
    ```

2. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure that:
   * You set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
   * The option `GATEWAY_TABLE` is set to "disabled" if your nexthop computer is on your LAN (most likely it is, as you wouldn't want to send unencrypted traffic over your WAN). The connection will not work if GATEWAY_TABLE is not set to "disabled" for LAN computers.
   * The option `VPN_PROVIDER` is set to "nexthop".
   * The option `VPN_ENDPOINT_IPV4` and `VPN_ENDPOINT_IPV6` is set to the IP of the computer on your network that is running the VPN client that you want to redirect traffic to. If your VPN computer does not support IPv6, then only set the IPv4 address.
   * The option `DEV` is set to the bridge interface that your VPN computer is on, for example "br0" for main LAN or "br6" for VLAN 6 (i.e.: VLAN X is on interface brX).

3. Run the split-vpn up command in this folder to bring up the rules to force traffic to the VPN. Change "br0" to the interface your VPN computer is on, and "mycomputer" to the nickname you want to refer to this computer with when you bring down the VPN connection.

    ```sh
    /etc/split-vpn/vpn/updown.sh br0 up mycomputer
    ```

      * If you need to bring down the tunnel and resume normal Internet access to your forced clients, run the following commands in this folder:

      ```sh
      cd /etc/split-vpn/nexthop/mycomputer
      /etc/split-vpn/vpn/updown.sh br0 down mycomputer
      ```

4. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

5. If everything is working, create a run script called `run-vpn.sh` in the current directory so you can easily run this configuration. Fill the script with the following contents:

    ```sh
    #!/bin/sh

    # Load configuration and bring routes up
    cd /etc/split-vpn/nexthop/mycomputer
    . ./vpn.conf
    /etc/split-vpn/vpn/updown.sh ${DEV} up mycomputer
    ```

    * Modify the `cd` line to point to the correct directory.
    * **Optional**: If you want to block Internet access to forced clients if the VPN tunnel is brought down with the updown script, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.

6. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

7. If your VPN provider doesn't support IPv6, it is recommended to disable IPv6 for that VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays. If you don't disable IPv6, clients on that network will try to communicate over IPv6 first and fail, then fallback to IPv4. This creates a delay that can be avoided if IPv6 is turned off completely for that network or client.

</details>
	
<details>
  <summary>Click here to see the instructions for Unifi OS' site-to-site.</summary>

  * **PREREQUISITE:** Make sure that your site-to-site network is created in your Unifi Console, and make sure that you added the remote subnet under the site-to-site network's "Remote Subnets" option.

1. Run the `ip route` command to find out the name of your site-to-site interface. Replace "192.168.99.0/24" in the command below with your own remote subnet.

    ```sh
    ip route show 192.168.99.0/24
    ```

    * You should see output that looks like the following. This example shows an interface name of vti64 or tun0, but yours might be a higher number depending on how many site-to-site networks you have setup on the router. This name will be different for each site-to-site network if you have multiple.

      * **For IPSec site-to-site:** *192.168.99.0/24 **dev vti64** proto static scope link metric 30*
      * **For OpenVPN site-to-site:** 192.168.99.0/24 **via 192.168.99.4 dev tun0** scope link
        * In this example, the interface name is `tun0` and the remote gateway IP is `192.168.99.4`.

    * If you do not get any output from the above command, double check that you already added the site-to-site network in your Unifi Console, and make sure you used the correct remote subnet in the settings and the above command.

2. Create a directory for your VPN configuration, and copy the sample vpn.conf from `/etc/split-vpn/vpn/vpn.conf.sample`. "site1" is used as an example below to refer to the site-to-site network.

    ```sh
    mkdir -p /etc/split-vpn/nexthop/site1
    cd /etc/split-vpn/nexthop/site1
    cp /etc/split-vpn/vpn/vpn.conf.sample vpn.conf
    ```

3. Edit the `vpn.conf` file with your desired settings. See the explanation of each setting [below](#configuration-variables). Make sure to change the following options:

   * Set one of the `FORCED_*` options to choose which clients or VLANs you want to force through the VPN.
   * Set `BYPASS_MASQUERADE_IPV4` to "ALL".
   * Set `VPN_PROVIDER` to "nexthop".
   * For IPSec site-to-site, set `VPN_ENDPOINT_IPV4` to the IP of the remote router on the remote subnet that you want to route traffic through. For example, set this to "192.168.99.1" if the remote subnet is 192.168.99.0/24 and the remote router is at 192.168.99.1.
    * For OpenVPN site-to-site, set `VPN_ENDPOINT_IPV4` to the IP of the remote gateway on the VPN network. See Step 1 above for how to find the remote gateway IP for OpenVPN site-to-site.
   * Set `GATEWAY_TABLE` to "disabled".
   * For IPSec site-to-site, set `MSS_CLAMPING_IPV4` to "1382". If you do not set this option, some sites might stall. This setting might be needed for OpenVPN site-to-site in some cases.
   * Set `DEV` to the  interface name for your site-to-site (for example `vti64` or `tun0`). See Step 1 above for how to lookup the interface name.

4. Run the split-vpn up command in this folder to bring up the rules to force traffic to the VPN. Change "vti64" to your site-to-site network's interface name, and "site1" to the nickname you want to give your VPN.

    ```sh
    /etc/split-vpn/vpn/updown.sh vti64 up site1
    ```

      * If you need to bring down the tunnel and resume normal Internet access to your forced clients, run the following commands in this folder:

          ```sh
          cd /etc/split-vpn/nexthop/site1
          /etc/split-vpn/vpn/updown.sh vti64 down site1
          ```

5. If the connection works, check each client to make sure they are on the VPN. See the FAQ question [How do I check my clients are on the VPN?](#faq) below.

6. If everything is working, create a run script called `run-vpn.sh` in the current directory so you can easily run this configuration. Fill the script with the following contents:

    ```sh
    #!/bin/sh

    # Load configuration and bring routes up
    cd /etc/split-vpn/nexthop/site1
    . ./vpn.conf
    /etc/split-vpn/vpn/updown.sh ${DEV} up site1
    ```

    * Modify the `cd` line to point to the correct directory.
    * **Optional**: If you want to block Internet access to forced clients if the VPN tunnel is brought down with the updown script, set `KILLSWITCH=1` and `REMOVE_KILLSWITCH_ON_EXIT=0` in the `vpn.conf` file.
    * Make sure to give the script executable permission so it can run with the following command.
        ```sh
        chmod +x run-vpn.sh
        ```

7. Now you can exit the SSH session. If you would like to start the VPN client at boot, please read on to the next section.

8. Unifi OS' site-to-site doesn't support IPv6, so it is recommended to disable IPv6 for forced VLAN in the Unifi Network settings, or on the client, so that you don't encounter any delays.

</details>

## How do I run this at boot?

Boot scripts on UnifiOS 1.x are supported via the [UDM Utilities Boot Script](https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script). On UnifiOS 2.x and up, boot scripts are supported natively via systemd. The boot script survives across firmware upgrades and reboots.
	
<details>
  <summary>Click here to see the instructions for how to set up the boot script.</summary>

  1. Create a master run script under `/etc/split-vpn/run-vpn.sh` that will be used to run your VPNs. In this master script, call the run script of each VPN client that you want to run at boot (the run script should have been created if you followed the instructions [above](#how-do-i-use-this)). For example, here we are running a wireguard client and an OpenVPN client.

      ```sh
      #!/bin/sh
      /etc/split-vpn/wireguard/mullvad/run-vpn.sh
      /etc/split-vpn/openvpn/nordvpn/run-vpn.sh
      ```

      * You can run as many VPN clients as you want.
        * Make sure you use a separate directory for each VPN server, and give each one a vpn.conf file with the clients you wish to force through them.
        * Make sure the options `ROUTE_TABLE`, `MARK`, `PREFIX`, `PREF`, and `DEV` are unique for each `vpn.conf` file so the different VPN servers don't share the same tunnel device, route table, or fwmark. If you are using nexthop, DEV does not have to be unique.
        * Make sure you first created the run-vpn.sh run scripts in each configuration directory as instructed above in [How do I use this?](#how-do-i-use-this).
        * For wireguard-go, only one client is supported. If you want to run multiple wireguard instances, use the wireguard kernel module instead.

  2. Give the master run script executable permissions.

      ```sh
      chmod +x /etc/split-vpn/run-vpn.sh
      ```

  3. Install the boot service for your device.

      * For UnifiOS 1.x, set-up UDM Utilities Boot Script by following the instructions [here](https://github.com/boostchicken/udm-utilities/blob/master/on-boot-script/README.md) first. Then install the boot script by running:
          ```sh
          curl -o /mnt/data/on_boot.d/99-run-vpn.sh https://raw.githubusercontent.com/peacey/split-vpn/main/examples/boot/run-vpn.sh
          chmod +x /mnt/data/on_boot.d/99-run-vpn.sh
          ```

      * For UnifiOS 2.x and up, run the following commands to install a systemd boot service.

          ```sh
          curl -o /etc/systemd/system/run-vpn.service https://raw.githubusercontent.com/peacey/split-vpn/main/examples/boot/run-vpn.service
          systemctl daemon-reload && systemctl enable run-vpn
          ```
          * Note the default systemd service is set to restart automatically on failure. If you do not want this behaivour, modify `/etc/systemd/system/run-vpn.service` and remove the `Restart=...` line.

  4. That's it. Now the VPN will start at every boot.

  5. Note that there is a short period between when the router starts and when this script runs. This means there is a few seconds when the router starts up when your forced clients **WILL** have access to your WAN and might leak their real IP, because the kill switch has not been activated yet. If you want a more secure configuration, read the question *How can I block Internet access until after this script runs at boot?* in the [FAQ below](#faq) to see how to solve this problem and block Internet access until after this script runs.

</details>

## Uninstallation Instructions
	
First, if you are running any split-vpn configurations, make sure to bring down the VPN before uninstalling. Alternatively, you can just restart after uninstalling.
  
**Option 1.** To uninstall everything including the script and configurations, simply run the following to remove the split-vpn directory in `/mnt/data` or `/data` and your boot scripts if using any.
  
```sh
rm -rf /mnt/data/split-vpn /data/split-vpn /etc/split-vpn
rm -rf /mnt/data/on_boot.d/99-run-vpn.sh /etc/systemd/system/run-vpn.service
```
  
**Option 2.** To uninstall only the scripts but keep the configurations in case you want to re-install in the future, run the following to delete only the `split-vpn/vpn` directory and boot scripts. Configuration files will be kept in your `split-vpn` directory. 
  
```sh
rm -rf /mnt/data/split-vpn/vpn /data/split-vpn/vpn /etc/split-vpn
rm -rf /mnt/data/on_boot.d/99-run-vpn.sh /etc/systemd/system/run-vpn.service
```
   
## Performance Testing

Throughput and performance tests for different VPN types can be found [here](Performance_Testing.md).

## FAQ

<details>
    <summary>How do I check my clients are on the VPN?</summary>

 * On your client, check if you are seeing the VPN IPs when you visit http://whatismyip.host/. You can also test from command line, by running the following commands from your clients. Make sure you are not seeing your real IP anywhere, either IPv4 or IPv6.
      ```sh
      curl -4 ifconfig.co
      curl -6 ifconfig.co
      ```
      If you are seeing your real IPv6 address above, make sure that you are forcing your client through IPv6 as well as IPv4, by forcing through interface, MAC address, or the IPv6 directly. If IPv6 is not supported by your VPN provider, the IPv6 check will time out and not return anything. You should never see your real IPv6 address.
* Check for DNS leaks with the Extended Test on https://www.dnsleaktest.com/. If you see a DNS leak, try redirecting DNS with the `DNS_IPV4_IP` and `DNS_IPV6_IP` options, or set `DNS_IPV6_IP="REJECT"` if your VPN provider does not support IPv6.
* Check for WebRTC leaks in your browser by visiting https://browserleaks.com/webrtc. If WebRTC is leaking your IPv6 IP, you need to disable WebRTC in your browser (if possible), or disable IPv6 completely by disabling it directly on your client or through the Unifi Network settings for the client's VLAN.

</details>

<details>
  <summary>Can I route clients to different VPN servers?</summary>

  * Yes you can. Create a master run script as instructed in [How do I run this at boot?](#how-do-i-run-this-at-boot) and add your individual VPN run scripts to that. Do not install the boot service if you do not want to run the script at boot.
  * Multiple wireguard-go clients is currently not supported. Use the kernel module for multiple wireguard clients.

</details>

<details>
  <summary>How can I block Internet access until after this script runs at boot?</summary>

  * If you want to ensure that there is no Internet access BEFORE this script runs at boot, you can add blackhole static routes in the Unifi Settings that will block all Internet access (including non-VPN Internet) until they are removed by this script. The blackhole routes will be removed when this script starts to restore Internet access only after the killswitch has been activated. If you want to do this for maximum protection at boot up, follow these instructions:

      1. Go to your Unifi Network Settings, and add the following static routes. If you're using the New Settings, this is under Advanced Features -> Advanced Gateway Settings -> Static Routes. For Old Settings, this is under Settings -> Routing and Firewall -> Static Routes. Add these routes which cover all IP ranges:

          * **Name:** VPN Blackhole. **Destination:** 0.0.0.0/1. **Static Route Type:** Black Hole. **Enabled.**
          * **Name:** VPN Blackhole. **Destination:** 128.0.0.0/1. **Static Route Type:** Black Hole. **Enabled.**
          * **Name:** VPN Blackhole. **Destination:** ::/1. **Static Route Type:** Black Hole. **Enabled.**
          * **Name:** VPN Blackhole. **Destination:** 8000::/1. **Static Route Type:** Black Hole. **Enabled.**

      2. In your vpn.conf, set the option `REMOVE_STARTUP_BLACKHOLES=1`. This is required or else the script will not delete the blackhole routes at startup, and you will not have Internet access on ANY client, not just the VPN-forced clients, until you delete the blackhole routes manually or disable them in the Unifi Settings.

      3. In your run script above, make sure you did NOT comment out the pre-up line. That is the line that removes the blackhole routes at startup.

      4. **Note that once you do this, you will lose Internet access for ALL clients until you run the VPN run script above**, or were running it before with the `REMOVE_STARTUP_BLACKHOLES=1` option. The split-vpn script stays running in the background to monitor if the the blackhole routes are added by the system again (which happens when your IP changes or when route settings are changed). The blackhole routes will be deleted immediately when they're added by the system.

</details>

<details>
  <summary>Can I force/exempt domains to the VPN instead of just IPs?</summary>

  * Yes you can if you are using dnsmasq or pihole. Please see the [instructions here](ipsets/README.md) for how to set this up.

</details>

<details>
  <summary>How can I force/exempt a large number of network subnets?</summary>
	
  * You can add your network subnets to a kernel ipset, and force/exempt that ipset via the `FORCED_IPSETS` or `EXEMPT_IPSETS` option in `vpn.conf`. Kernel ipsets are very efficient and can support up to 65536 elements each.
  * Here is an example on how to use ipsets with this script.
	
    1. Create a file under `/etc/split-vpn/ipsets/networklist.txt` and add the networks to it. Here we will use vim to create and edit the file.
        ```sh
        mkdir -p /etc/split-vpn/ipsets
        cd /etc/split-vpn/ipsets
        vim networklist.txt
        ```
        * Press `i` to start editing in vim, and put your network entries one on each line. You can also right click -> paste to paste many entries. Press `ESC` when done to exit insert mode, and type `:wq` to save and exit.
	
    2. Download and run the `add-network-ipset.sh` script which will create the ipset and add the network subnets from the file above into the ipset.
        ```sh
        curl -Lo add-network-ipset.sh https://raw.githubusercontent.com/peacey/split-vpn/main/examples/ipsets/add-network-ipset.sh
        chmod +x add-network-ipset.sh
        ./add-network-ipset.sh
        ```
        * This script will create an ipset called VPN_LIST (as well as VPN_LIST4 and VPN_LIST6, the IPv4 and IPv6 parts of the list). You can change this name by modifying the `IPSET_NAME` variable at the top of the script.
        * The script uses `/etc/split-vpn/ipsets/networklist.txt` as the location of the list file. You can change that by modifying the `LIST_FILE` variable in the script.
	
    3. Check that the ipset was created and the subnets were added using the ipset utility.
        ```sh
        ipset list VPN_LIST4
        ipset list VPN_LIST6
        ```
	
    4. If everything looks good, modify your `vpn.conf` file to force or exempt this ipset, then restart the VPN.
	
        * If you want to force or exempt these subnets, add the ipset `VPN_LIST` to the `FORCED_IPSETS` or `EXEMPT_IPSETS` variable. Specify 'dst' if these are destination subnets, or 'src' if these are source subnets. For example, to force this list of network subnets if they are destinations, then set

          ```sh
          FORCED_IPSETS="VPN_LIST:dst"
          ```

        * Note that the variables `FORCED_IPSETS` and `EXEMPT_IPSETS` apply to all router-connected clients, not just the ones defined in the `FORCED_SOURCE_*` options. If you want more granular control, such as forcing a different list for different clients or only for specific clients, then consider using `CUSTOM_FORCED_RULES_IPV4` or `CUSTOM_FORCED_RULES_IPV6` instead, which offers much more flexibility. See the [configuration variables](#configuration-variables) below for more information.

      5. If you are using a boot script to start the VPN at boot, make sure to run the `add-network-ipset.sh` script before running the split-vpn script by adding the following line to the top of your boot script. If you do not run the ipset creation script first, the VPN script will error because the configured ipset was not found.

          ```sh
          /etc/split-vpn/ipsets/add-network-ipset.sh
          ```
	
</details>	
		
<details>
  <summary>I cannot access my WAN IP from a VPN-forced client (i.e. hairpin NAT does not work). What do I do?</summary>

  * In order for hairpin NAT to work, you need to exempt your WAN IPs from the VPN. You can do this in one of two ways:

    * If your WAN IP address is static and doesn't change, add your WAN's IPv4 address to `EXEMPT_DESTINATIONS_IPV4` and your IPv6 address to `EXEMPT_DESTINATIONS_IPV6`.

    * If your WAN IP changes often and you do not want to keep updating it in the script, exempt the Unifi provided IP sets that store your IPs by using the `EXEMPT_IPSETS` option. These IP sets are labelled `UBIOS_ADDRv4_<interface>`/`UBIOS_ADDRv6_<interface>` and are dynamically updated by Unifi when your WAN IP changes. For example, to exempt the WAN IP of eth8, use the following option. Note that for prefix delegation, the WAN IPv6 addresses are stored on the bridge interfaces, not the eth interfaces so make sure to add the bridge interface for IPv6 hairpin NAT.

      ```sh
      EXEMPT_IPSETS="UBIOS_ADDRv4_eth8:dst UBIOS_ADDRv6_br0:dst"
      ```

</details>

<details>
  <summary>How do I safely shutdown the VPN?</summary>

  * Run the following commands for your VPN type to bring down the VPN. Kill switch and iptables rules will only be removed if the option `REMOVE_KILLSWITCH_ON_EXIT` is set to 1.
  * If you set `REMOVE_KILLSWITCH_ON_EXIT=0` and want to recover Internet access for forced clients, please read the next question after you bring down the VPN.

    * **OpenVPN:** Send the openvpn process the TERM signal to bring it down.

        1. If you want to kill all openvpn instances.

            ```sh
            killall -TERM openvpn
            ```

        2. If you want to kill a specific openvpn instance using tun0.

            ```sh
            kill -TERM $(pgrep -f "openvpn.*tun0")
            ```

    * **WireGuard (kernel module):** Change to the directory of your vpn.conf configuration and run the wg-quick down command.

      ```sh
      cd /etc/split-vpn/wireguard/mullvad
      wg-quick down ./wg0.conf
      ```

    * **wireguard-go:** Stop the container and run the split-vpn down command in the wireguard configuration directory.

      ```sh
      cd /mnt/data/wireguard
      podman stop wireguard
      /etc/split-vpn/vpn/updown.sh wg0 down
      ```

    * **OpenConnect:** Send the openconnect process the TERM signal to bring it down.

        1. If you want to kill all openconnect instances.

            ```sh
            killall -TERM openconnect
            ```

        2. If you want to kill a specific openconnect instance using tun0.

            ```sh
            kill -TERM $(pgrep -f "openconnect.*tun0")
            ```
	
    * **StrongSwan:** Stop and delete the strongswan container.
	
      ```sh
      podman rm -f strongswan-vti256
      ```

    * **Nexthop:** Change to the directory of your vpn.conf configuration and run the split-vpn down command. Make sure to use the correct nickname and interface.

      ```sh
      cd /etc/split-vpn/nexthop/mycomputer
      /etc/split-vpn/vpn/updown.sh br0 down mycomputer
      ```

</details>

<details>
  <summary>The VPN exited or crashed and now I can't access the Internet on my devices. What do I do?</summary>

  * When the VPN process crashes, there is no cleanup done for the iptables rules and the kill switch is still active (if the kill switch is enabled). This is also the case for a clean exit when you set the option `REMOVE_KILLSWITCH_ON_EXIT=0`. This is a safety feature so that there are no leaks if the VPN crashes. To recover the connection, do the following:

    * If you don't want to delete the kill switch and leak your real IP, re-run the run script or command to bring the VPN back up again.

    * If you want to delete the kill switch so your forced clients can access your normal Internet again, change to the directory with the vpn.conf file and run the following command (replace tun0 with the device you defined in the config file). This command applies to all VPN types.

        ```sh
        cd /etc/split-vpn/openvpn/nordvpn
        /etc/split-vpn/vpn/updown.sh tun0 force-down
        ```

    * If you added blackhole routes and deleted the kill switch in the previous step, make sure to disable the blackhole routes in the Unifi Settings or you might suddenly lose Internet access when the blackhole routes are re-added by the system.

</details>

<details>
  <summary>How do I enable or disable the kill switch and what does it do?</summary>

  * The kill switch disables Internet access for VPN-forced clients if the VPN crashes or exits. This is good for when you do not want to leak your real IP if the VPN crashes or exits prematurely. Follow the instructions below to enable or disable the kill switch.

    1. To enable the kill switch, set `KILLSWITCH=1` in the `vpn.conf` file. If you want the kill switch to remain even when you bring down the VPN cleanly (not just when it crashes), then set `REMOVE_KILLSWITCH_ON_EXIT=0` as well.

    2. To disable the kill switch, set `KILLSWITCH=0` and `REMOVE_KILLSWITCH_ON_EXIT=1`. Note that there will be nothing preventing your VPN-forced clients from leaking their real IP if you disable the kill switch.

    3. If you previously had the kill switch enabled and want to disable it after a crash or exit to recover Internet access, read the previous question.

</details>

<details>
  <summary>How do I enable or disable the VPN blackhole routes and what do they do?</summary>

  * The VPN blackhole routes are added to the custom route table before the VPN routes are added. The blackhole routes prevent Internet access on VPN-forced clients if the VPN started successfully but the VPN routes were not added because of some problem. Note this is not the same as the Unifi system-wide blackhole routes to prevent Internet access on startup before the VPN script runs (outlined in the boot section above).

    1. To enable the VPN blackhole routes, make sure `DISABLE_BLACKHOLE=0` or the variable is not set in your vpn.conf (default).

    2. To disable the VPN blackhole routes, set `DISABLE_BLACKHOLE=1` in your vpn.conf. This is not recommended unless you do not care about your real IP leaking.

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

  * If IPv6 is not supported by your VPN provider, IPv6 traffic should time out or be refused. For additional security if your VPN provider doesn't support IPv6, it is recommended to set the `DNS_IPV6_IP` option to "REJECT", or disable IPv6 for that network in the Unifi Network settings, so that IPv6 DNS leaks do not occur.

</details>

<details>
  <summary>Why am I seeing my real IPv6 address when doing a WebRTC test?</summary>

  * WebRTC is an audio/video protocol that allows browsers to get your IPs via JavaScript. WebRTC cannot be completely disabled at the network level because some browsers check the network interface directly to see what IP to return. Since IPv6 has global IPs directly assigned to the network interface, your non-VPN global IPv6 can be directly seen by the browser and leaked to WebRTC JavaScript calls. To solve this, you can do one of the following.

    * Disable WebRTC on your browser (not all browsers allow you to). Use a browser like Firefox that allows you to disable WebRTC.
    * Disable JavaScript completely on your browser (which will break most sites).
    * Disable IPv6 completely either directly on the client (if you can), or by using the Unifi Network settings to turn off IPv6 for the client's VLAN.

</details>

<details>
  <summary>My VPN provider doesn't support IPv6. Why do my forced clients have a delay in communicating to the Internet?</summary>

  * If your VPN provider doesn't support IPv6 but you have IPv6 enabled on the network, clients will attempt to communicate over IPv6 first then fallback to IPv4 when the connection fails, since IPv6 is not supported on the VPN.

  * To avoid this delay, it is recommended to disable IPv6 for that network/VLAN in the Unifi Network settings, or on the client directly. This ensures that the clients only use IPv4 and don't have to wait for IPv6 to time out first.

</details>

<details>
  <summary>Does the VPN still work when my IP changes because of lease renewals or other disconnect reasons?</summary>

  * **For OpenVPN:** Yes, as long as you add the `--ping-restart X` option to the openvpn command line when you run it. This ensures that if there is a network disconnect for any reason, the OpenVPN client will restart and try to re-configure itself after X seconds until it connects again. The killswitch will still be active during the restart to block non-VPN traffic as long as you set `REMOVE_KILLSWITCH_ON_EXIT=0` in the config.

  * **For WireGuard:** The WireGuard protocol is practically stateless, so IP changes will not affect the connection.

  * **For OpenConnect:** Yes, as long as you used the `--restart on-failure` option to podman. This ensures that if there is a network disconnect or unexpected exit for any reason, the OpenConnect client will restart and try to re-configure itself until it connects again. The killswitch will still be active during the restart to block non-VPN traffic as long as you set `REMOVE_KILLSWITCH_ON_EXIT=0` in the config.
	
  * **For StrongSwan:** Yes, the StrongSwan daemon will automatically reconnect when the connection is working again.

</details>

<details>
  <summary>Does this script work with Layer 3 switches?</summary>

  * Yes, but not all options are compatible on networks with L3 switches. Specifically, any option matching on a client's MAC address or interface will not work for networks where the L3 switch is assigned as the gateway. This is because when a L3 switch, rather than the Unifi router, is configured as the Gateway for a Network, the switch acts as a router and overrides the MAC address of packets sent to the router. This means the packets that arrive on the router have the switch's MAC address and come through a special inter-VLAN interface instead of the regular brX VLAN interfaces.

  * Instead, try to match on the IP of the client instead of the MAC or interface if you are using a L3 switch as a gateway.

  * Layer 3 switches acting in Layer 2 (not configured as the gateway) will still work fine with options that match on MAC or interface, since they are not acting as a router.

</details>

<details>
  <summary>What does this really do to my router?</summary>

  * This script only does the following.

    1. Adds custom iptables chains and rules to the mangle, nat, and filter tables. You can see them with the following commands (assuming you set `PREFIX=VPN_`).

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

    2. Adds policy-based routes to redirect marked traffic to the custom tables. You can see them with the following command (look for the fwmark you defined in your config or 0x169 if using default).

        ```sh
        ip rule
        ip -6 rule
        ```

    4. Stays running in the background to monitor the policy-based routes every second for any deletions caused by the Unifi operating system, and re-adds them if deleted. Unifi OS removes the custom policy-based routes when the WAN IP changes. You can see the script running with:

        ```sh
        ps | grep updown.sh
        ```

    5. Writes logs in each VPN configuration's directory. Logs are overwritten at every run.

</details>

<details>
  <summary>Something went wrong. How can I debug?</summary>

  * First, force the VPN down by following the questions above *How do I safely shutdown the VPN?* and *The VPN exited or crashed and now I can't access the Internet on my devices. What do I do?*
    * Try to start the VPN again after you brought the rules down and see if you still encounter the problem.
  * Check the log files.
    * For OpenVPN, first check the openvpn.log file in the VPN server's directory for any errors.
    * For WireGuard, check wireguard.log after you run your run script or check the output of wg-quick up. For wireguard-go, check the output when you run your run script. Make sure you received a handshake in WireGuard or the connection will not work. If you did not receive a handshake, double check your configuration's Private and Public key and other variables.
    * For OpenConnect, check the openconnect.log file in the VPN server's directory for any errors.
	* For StrongSwan, check the splitvpn-up.log in the VPN server's directory, and check `podman logs strongswan-vti256`.
  * Check that the iptables rules, policy-based routes, and custom table routes agree with your configuration. See the previous question for how to look this up.
  * If you want to see which line the scripts failed on, open the `updown.sh` and `add-vpn-iptables-rules.sh` scripts and replace the `set -e` line at the top with `set -xe` then rerun the VPN. The `-x` flag tells the shell to print every line before it executes it.
  * Post a bug report if you encounter any reproducible issues.

</details>

## Configuration variables

<details>
<summary>Settings are modified in vpn.conf. Multiple entries can be entered for each setting by separating the entries with spaces. Click here to see all the settings.</summary>

<details>
  <summary>FORCED_SOURCE_INTERFACE</summary>

  * Force all traffic coming from a source interface through the VPN.
  * Default LAN is br0, and other LANs are brX, where X = VLAN number.

  ```ini
  Format: [INTERFACE NAME]
  Example: FORCED_SOURCE_INTERFACE="br6 br8"
  ```
</details>

<details>
  <summary>FORCED_SOURCE_IPV4</summary>

  * Force all traffic coming from a source IPv4 through the VPN.
  * IP can be entered in CIDR format to cover a whole subnet.

  ```ini
  Format: [IP/nn]
  Example: FORCED_SOURCE_IPV4="192.168.1.1/32 192.168.3.0/24"
  ```
</details>

<details>
  <summary>FORCED_SOURCE_IPV6</summary>

  * Force all traffic coming from a source IPv6 through the VPN.
  * IP can be entered in CIDR format to cover a whole subnet.

  ```ini
  Format: [IP/nn]
  Example: FORCED_SOURCE_IPV6="fd00::2/128 2001:1111:2222:3333::/56"
  ```
</details>

<details>
  <summary>FORCED_SOURCE_MAC</summary>

  * Force all traffic coming from a source MAC through the VPN.

  ```ini
  Format: [MAC]
  Example: FORCED_SOURCE_MAC="00:aa:bb:cc:dd:ee 30:08:d7:aa:bb:cc"
  ```
</details>

<details>
  <summary>FORCED_DESTINATIONS_IPV4</summary>

  * Force IPv4 destinations to the VPN for all VPN-forced clients.

  ```ini
  Format: [IP/nn]
  Example: FORCED_DESTINATIONS_IPV4="1.1.1.1"
  ```
</details>

<details>
  <summary>FORCED_DESTINATIONS_IPV6</summary>

  * Force IPv6 destinations to the VPN for all VPN-forced clients.

  ```ini
  Format: [IP/nn]
  Example: FORCED_DESTINATIONS_IPV6="2001:1111:2222:3333::2"
  ```
</details>

<details>
  <summary>FORCED_LOCAL_INTERFACE</summary>

  * Force local router traffic going out of these interfaces to go through the VPN instead, for both IPv4 and IPv6 traffic. This does not include routed traffic, only local traffic generated by the router itself.
  * This option can have unintended consequences and not all router features might work with it. It is recommended not to use this option unless you are prepared to debug if something goes wrong.
  * For UDM-Pro, UDM-SE, or UXG-Pro, set to "eth8" for RJ45 WAN port, or "eth9" for SFP+ WAN port, or "eth8 eth9" for both.
  * For UDM Base, set to "eth4" for the RJ45 WAN port.

  ```ini
  Format: [INTERFACE NAME]
  Example: FORCED_LOCAL_INTERFACE="eth8 eth9"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_IPV4</summary>

  * Exempt IPv4 sources from the VPN. This allows you to create exceptions to the force rules above. For example, if you forced a whole interface with FORCED_SOURCE_INTERFACE, you can selectively choose clients from that VLAN to exclude.

  ```ini
  Format: [IP/nn]
  Example: EXEMPT_SOURCE_IPV4="192.168.1.2/32 192.168.3.8/32"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_IPV6</summary>

  * Exempt IPv6 sources from the VPN. This allows you to create exceptions to the force rules above.

  ```ini
  Format: [IP/nn]
  Example: EXEMPT_SOURCE_IPV6="2001:1111:2222:3333::2 2001:1111:2222:3333::10"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_MAC</summary>

  * Exempt MAC sources from the VPN. This allows you to create exceptions to the force rules above.

  ```ini
  Format: [MAC]
  Example: EXEMPT_SOURCE_MAC="00:aa:bb:cc:dd:ee 30:08:d7:aa:bb:cc"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_IPV4_PORT</summary>

  * Exempt an IPv4:Port source from the VPN.
  * This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN. For example, you can tunnel all traffic through the VPN for some client, but have port 22 still be accessible over the LAN/WAN so you can SSH to it normally.
  * A single entry can have up to 15 multiple ports by separating the ports with commas.
  * Ranges of ports can be defined with a colon like 5000:6000, and take up two ports in the entry.
  * Protocol can be tcp, udp or both.

  ```ini
  Format: [tcp/udp/both]-[IP Source]-[port1,port2:port3,port4,...]
  Example: EXEMPT_SOURCE_IPV4_PORT="tcp-192.168.1.1-22,32400,80:90,443 both-192.168.1.3-53"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_IPV6_PORT</summary>

  * Exempt an IPv6:Port source from the VPN.
  * This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN.
  * A single entry can have up to 15 multiple ports by separating the ports with commas.
  * Ranges of ports can be defined with a colon like 5000:6000, and take up two ports in the entry.
  * Protocol can be tcp, udp or both.

  ```ini
  Format: [tcp/udp/both]-[IP Source]-[port1,port2:port3,port4,...]
  Example: EXEMPT_SOURCE_IPV6_PORT="tcp-fd00::69-22,32400,80:90,443 both-fd00::2-53"
  ```
</details>

<details>
  <summary>EXEMPT_SOURCE_MAC_PORT</summary>

  * Exempt a MAC:Port source from the VPN.
  * This allows you to create exceptions on a port basis, so you can selectively choose which services on a client to tunnel through the VPN and which to tunnel through the default LAN/WAN.
  * A single entry can have up to 15 multiple ports by separating the ports with commas.
  * Ranges of ports can be defined with a colon like 5000:6000, and take up two ports in the entry.
  * Protocol can be tcp, udp or both.

  ```ini
  Format: [tcp/udp/both]-[MAC Source]-[port1,port2:port3,port4,...]
  Example: EXEMPT_SOURCE_MAC_PORT="both-30:08:d7:aa:bb:cc-22,32400,80:90,443"
  ```
</details>

<details>
  <summary>EXEMPT_DESTINATIONS_IPV4</summary>

  * Exempt IPv4 destinations from the VPN for all VPN-forced clients.

  ```ini
  Format: [IP/nn]
  Example: EXEMPT_DESTINATIONS_IPV4="192.168.1.0/24 10.0.5.3/32"
  ```
</details>

<details>
  <summary>EXEMPT_DESTINATIONS_IPV6</summary>

  * Exempt IPv6 destinations from the VPN for all VPN-forced clients.

  ```ini
  Format: [IP/nn]
  Example: EXEMPT_DESTINATIONS_IPV6="fd62:1200:1300:1400::2/32 2001:1111:2222:3333::/56"
  ```
</details>

<details>
  <summary>FORCED_IPSETS</summary>

  * Force these IP sets through the VPN.
  * IP sets need to be created before this script is run or the script will error. IP sets can be updated externally and will be matched dynamically. Each IP set entry consists of the IP set name and whether to match on source or destination for each field in the IP set.
  * These IP sets will be forced for every VPN-forced client. If you want to force different IP sets for different clients, use `CUSTOM_FORCED_RULES_IPV4` and  `CUSTOM_FORCED_RULES_IPV6` below.

  ```ini
  Note: src/dst needs to be specified for each IP set field.
  Format: Format: [IPSet Name]:[src/dst,src/dst,...]
  Example: FORCED_IPSETS="VPN_FORCED:dst IPSET_NAME:src,dst"
  ```
</details>

<details>
  <summary>EXEMPT_IPSETS</summary>

  * Exempt these IP sets from the VPN.
  * IP sets need to be created before this script is run or the script will error. IP sets can be updated externally and will be matched dynamically. Each IP set entry consists of the IP set name and whether to match on source or destination for each field in the IP set.
  * You can enable NAT hairpin by exempting UBIOS_ADDRv4_ethX:dst for IPv4 or UBIOS_ADDRv6_ethX:dst for IPv6 (where X = 8 for RJ45, or 9 for SFP+ WAN). For IPv6 prefix delegation, exempt UBIOS_ADDRv6_brX, where X = VLAN number (0 = LAN).
  * To allow communication with your VLAN subnets without hardcoding the subnets using `EXEMPT_DESTINATIONS_*` options above, exempt the UBIOS_NETv4_brX:dst ipset for IPv4 or UBIOS_NETv6_brX:dst for IPv6.
  * These IP sets will be exempt for every VPN-forced client. If you want to exempt different IP sets for different clients, use `CUSTOM_EXEMPT_RULES_IPV4` and  `CUSTOM_EXEMPT_RULES_IPV6` below.

  ```ini
  Note: src/dst needs to be specified for each IP set field.
  Format: Format: [IPSet Name]:[src/dst,src/dst,...]
  Example: EXEMPT_IPSETS="VPN_EXEMPT:dst IPSET_NAME:src,dst"
           EXEMPT_IPSETS="UBIOS_ADDRv4_eth8:dst UBIOS_ADDRv6_br0:dst UBIOS_NETv4_br0:dst UBIOS_NETv4_br5:dst"
  ```
</details>

<details>
  <summary>CUSTOM_FORCED_RULES_IPV4</summary>

  * Custom IPv4 rules that will be forced to the VPN.
  * The format of these rules is the matching portion of the iptables command, without the table, chain, and jump target.
  * Multiple rules can be added on separate lines.
  * These rules are added to the mangle table and the PREROUTING chain.
  * Opening and closing quotation marks must not be removed if using multiple lines.

  ```ini
  Format: [Matching portion of iptables command]
  Example:
    CUSTOM_FORCED_RULES_IPV4="
        -s 192.168.1.6
        -p tcp -s 192.168.1.10 --dport 443
        -m set --match-set VPN_FORCED dst -i br6
    "
  ```
</details>

<details>
  <summary>CUSTOM_FORCED_RULES_IPV6</summary>

  * Custom IPv6 rules that will be forced to the VPN.
  * The format of these rules is the matching portion of the iptables command, without the table, chain, and jump target.
  * Multiple rules can be added on separate lines.
  * These rules are added to the mangle table and the PREROUTING chain.
  * Opening and closing quotation marks must not be removed if using multiple lines.

  ```ini
  Format: [Matching portion of iptables command]
  Example:
    CUSTOM_FORCED_RULES_IPV6="
        -s fd62:1200:1300:1400::2/32
        -p tcp -s fd62:1200:1300:1400::10 --dport 443
        -m set --match-set VPN_FORCED dst -i br6
    "
  ```
</details>

<details>
  <summary>CUSTOM_EXEMPT_RULES_IPV4</summary>

  * Custom IPv4 rules that will be exempt from the VPN.
  * The format of these rules is the matching portion of the iptables command, without the table, chain, and jump target.
  * Multiple rules can be added on separate lines.
  * These rules are added to the mangle table and the PREROUTING chain.
  * Opening and closing quotation marks must not be removed if using multiple lines.

  ```ini
  Format: [Matching portion of iptables command]
  Example:
    CUSTOM_EXEMPT_RULES_IPV4="
        -s 192.168.1.6
        -p tcp -s 192.168.1.10 --dport 443
        -m set --match-set VPN_EXEMPT dst -i br6
    "
  ```
</details>

<details>
  <summary>CUSTOM_EXEMPT_RULES_IPV6</summary>

  * Custom IPv6 rules that will be exempt from the VPN.
  * The format of these rules is the matching portion of the iptables command, without the table, chain, and jump target.
  * Multiple rules can be added on separate lines.
  * These rules are added to the mangle table and the PREROUTING chain.
  * Opening and closing quotation marks must not be removed if using multiple lines.

  ```ini
  Format: [Matching portion of iptables command]
  Example:
    CUSTOM_EXEMPT_RULES_IPV6="
        -s fd62:1200:1300:1400::2/32
        -p tcp -s fd62:1200:1300:1400::10 --dport 443
        -m set --match-set VPN_EXEMPT dst -i br6
    "
  ```
</details>

<details>
  <summary>PORT_FORWARDS_IPV4</summary>

  * Forward ports on the VPN side to a local IPv4:port. Not all VPN providers support port forwards. The ports are usually given to you on the provider's portal.
  * Only one port per entry. Protocol can be tcp, udp or both.

  ```ini
  Format: [tcp/udp/both]-[VPN Port]-[Forward IP]-[Forward Port]
  Example: PORT_FORWARDS_IPV4="tcp-21674-192.168.1.1-50001 tcp-31683-192.168.1.1-22"
  ```
</details>

<details>
  <summary>PORT_FORWARDS_IPV6</summary>

  * Forward ports on the VPN side to a local IPv6:port. Not all VPN providers support port forwards. The ports are usually given to you on the provider's portal.
  * Only one port per entry. Protocol can be tcp, udp or both.

  ```ini
  Format: [tcp/udp/both]-[VPN Port]-[Forward IP]-[Forward Port]
  Example: PORT_FORWARDS_IPV6="tcp-21674-2001:aaa:bbbb:2acc::69-50001 tcp-31456-2001:aaa:bbbb:2acc::70-443"
  ```
</details>

<details>
  <summary>DNS_IPV4_IP, DNS_IPV4_PORT</summary>

  * Redirect DNS IPv4 traffic of VPN-forced clients to this IP and port.
  * If set to "DHCP", the DNS will try to be obtained from the DHCP options that the VPN server sends. DHCP option is only supported for OpenVPN and OpenConnect.
  * If set to "REJECT", DNS requests over IPv6 will be blocked instead.
  * Note that many VPN providers redirect all DNS traffic to their servers, so redirection to other Internet IPs might not work on all providers.
  * DNS redirects to a local address, or rejecting DNS traffic works for all providers.
    * Make sure to set DNS_IPV4_INTERFACE if redirecting to a local DNS address.

  ```ini
  Format: [IP] or "DHCP" or "REJECT"
  Example: DNS_IPV4_IP="1.1.1.1"
  Example: DNS_IPV4_IP="DHCP"
  Example: DNS_IPV4_IP="REJECT"
  Example: DNS_IPV4_PORT=53
  ```
</details>

<details>
  <summary>DNS_IPV4_INTERFACE</summary>

  * Set this to the interface (brX) the IPv4 DNS is on if your `DNS_IPV4_IP` is a local IP. Leave blank for non-local DNS.
  * Local DNS redirects will not work without specifying the interface.

  ```ini
  Format: [brX]
  Example: DNS_IPV4_INTERFACE="br0"
  ```
</details>

<details>
  <summary>DNS_IPV6_IP, DNS_IPV6_PORT</summary>

  * Redirect DNS IPv6 traffic of VPN-forced clients to this IP and port.
  * If set to "DHCP", the DNS will try to be obtained from the DHCP options that the VPN server sends. DHCP option is only supported for OpenVPN and OpenConnect.
  * If set to "REJECT", DNS requests over IPv6 will be blocked instead. The REJECT option is recommended to be enabled for VPN providers that don't support IPv6, to eliminate any IPv6 DNS leaks.
  * Note that many VPN providers redirect all DNS traffic to their servers, so redirection to other Internet IPs might not work on all providers.
  * DNS redirects to a local address, or rejecting DNS traffic works for all providers.
    * Make sure to set DNS_IPV6_INTERFACE if redirecting to a local DNS address.

  ```ini
  Format: [IP] or "DHCP" or "REJECT"
  Example: DNS_IPV6_IP="2606:4700:4700::64"
  Example: DNS_IPV6_IP="REJECT"
  Example: DNS_IPV6_PORT=53
  ```
</details>

<details>
  <summary>DNS_IPV6_INTERFACE</summary>

  * Set this to the interface (brX) the IPv6 DNS is on if your `DNS_IPV6_IP` is a local IP.
  * Leave blank for non-local DNS.
  * Local DNS redirects will not work without specifying the interface.

  ```ini
  Format: [brX]
  Example: DNS_IPV6_INTERFACE="br0"
  ```
</details>

<details>
  <summary>KILLSWITCH</summary>

  * Enable killswitch which adds an iptables rule to reject VPN-destined traffic that doesn't go out of the VPN.
  * This option is recommended for more secure configurations. Default is 0 (no killswitch).

  ```ini
  Format: 0 or 1
  Example: KILLSWITCH=1
  ```
</details>

<details>
  <summary>REMOVE_KILLSWITCH_ON_EXIT</summary>

  * Whether to remove the killswitch on exit or not. Default is 1 (yes).
  * For more secure configurations, it is recommended to set this to 0 so that the killswitch is not removed in case the openvpn client crashes, disconnects, or restarts.
  * Setting this to 1 will remove the killswitch when the openvpn client restarts, which means clients might be able to communicate with your default WAN and leak your real IP while the openvpn client is restarting.

  ```ini
  Format: 0 or 1
  Example: REMOVE_KILLSWITCH_ON_EXIT=0
  ```
</details>

<details>
  <summary>REMOVE_STARTUP_BLACKHOLES</summary>

  * Enable this if you added blackhole routes in the Unifi Settings to prevent Internet access at system startup before the VPN script runs.
  * This option removes the blackhole routes to restore Internet access after the killswitch has been enabled.
  * If you do not set this to 1 and you added the blackhole routes, the VPN will not be able to connect at startup, and your Internet access will never be enabled until you manually remove the blackhole routes.
  * Set this to 0 only if you did not add any blackhole routes in Step 6 of the boot script instructions above.

  ```ini
  Format: 0 or 1
  Example: REMOVE_STARTUP_BLACKHOLES=1
  ```
</details>

<details>
  <summary>DISABLE_BLACKHOLE</summary>

  * Set this to 1 to disable the VPN blackhole routes that are added (the blackhole routes help prevent VPN-forced clients from accessing the Internet if the VPN routes are not added because an error).

  ```ini
  Format: 0 (default) or 1
  Example: DISABLE_BLACKHOLE=0
  ```
</details>

<details>
  <summary>VPN_PROVIDER</summary>

  * The VPN provider you are using with this script.
  * **Format:** "openvpn" for OpenVPN (default), "openconnect" for OpenConnect, "external" for WireGuard or StrongSwan, or "nexthop" for an external VPN client connected to another computer on your network.

  ```ini
  Example: VPN_PROVIDER="openvpn"
  ```
</details>

<details>
  <summary>VPN_ENDPOINT_IPV4</summary>

  * If using nexthop for `VPN_PROVIDER`, set this to the VPN endpoint's IPv4 address so that the gateway route can be automatically added for the VPN endpoint.
  * OpenVPN, OpenConnect, and WireGuard automatically passes the VPN endpoint IP to the script and will override this value.
  * For StrongSwan, this option must be commented out (appended with a #) for auto-assignment from StrongSwan.

  ```ini
  Format: [IP]
  Example: VPN_ENDPOINT_IPV4="2.2.2.2"
  ```
</details>

<details>
  <summary>VPN_ENDPOINT_IPV6</summary>

  * If using nexthop for `VPN_PROVIDER`, set this to the VPN endpoint's IPv6 address so that the gateway route can be automatically added for the VPN endpoint.
  * OpenVPN, OpenConnect, and WireGuard automatically passes the VPN endpoint IP to the script and will override this value.
  * For StrongSwan, this option must be commented out (appended with a #) for auto-assignment from StrongSwan.

  ```ini
  Format: [IP]
  Example: VPN_ENDPOINT_IPV6="2606:43:ee::23"
  ```
</details>

<details>
  <summary>GATEWAY_TABLE</summary>

  * Set this to the route table that contains the gateway route, "auto", or "disabled".
  * The Ubiquiti route tables are "201" for WAN1, "202" for WAN2, and "203" for U-LTE.
  * Default is "auto" which works with WAN failover and automatically changes the endpoint via gateway route when the WAN or gateway routes changes.
  * Set to "disabled" when using the nexthop configuration to connect to a LAN computer.

  ```ini
  Format: [Route Table Number] or "auto" (default), or "disabled".
  Example: GATEWAY_TABLE="auto"
           GATEWAY_TABLE="201"
  ```
</details>

<details>
  <summary>DISABLE_DEFAULT_ROUTE</summary>

  * Set this to 1 to disable adding the default route. This means only non-default routes the VPN sends will be added.
  * This option only works for OpenVPN and OpenConnect. For WireGuard, modify the AllowedIPs variable in your wireguard config so WireGuard doesn't add default routes.

  ```ini
  Format: 0 (default) or 1
  Example: DISABLE_DEFAULT_ROUTE=1
  ```
</details>

<details>
  <summary>WATCHER_TIMER</summary>

  * Set this to the timer to use for the rule watcher (in seconds). The script will wake up every N seconds to re-add rules if they're deleted by the system, or change gateway routes if they changed. Default is 1 second.

  ```ini
  Format: [Seconds]
  Example: WATCHER_TIMER=1
  ```
</details>

<details>
  <summary>BYPASS_MASQUERADE_IPV4</summary>

  * Bypass masquerade (SNAT) for these IPv4s.
  * This option should only be used if your VPN server is setup to know how to route the subnet you do not want to masquerade (e.g.: the "iroute" option in OpenVPN).
  * Set this option to ALL to disable masquerading completely.

  ```ini
  Format: [IP/nn] or "ALL"
  Example: BYPASS_MASQUERADE_IPV4="10.100.1.0/24"
  ```
</details>

<details>
  <summary>BYPASS_MASQUERADE_IPV6</summary>

  * Bypass masquerade (SNAT) for these IPv6s.
  * This option should only be used if your VPN server is setup to know how to route the subnet you do not want to masquerade (e.g.: the "iroute" option in OpenVPN).
  * Set this option to ALL to disable masquerading completely.

  ```ini
  Format: [IP/nn] or "ALL"
  Example: BYPASS_MASQUERADE_IPV6="fd64::/64"
  ```
</details>

<details>
  <summary>ROUTE_TABLE</summary>

  * The custom route table number.
  * If you are running multiple VPN configurations, this needs to be unique in each `vpn.conf`.

  ```ini
  Format: [Number]
  Example: ROUTE_TABLE=101
  ```
</details>

<details>
  <summary>MARK</summary>

  * The firewall mark that will be used to mark the packets destined to the VPN.	
  * If you are running multiple VPN configurations, this needs to be unique in each `vpn.conf`.
  * **Restrictions:** Ubiquiti uses some firewall mark values internally, so the MARK used in this script must meet the following conditions:
    * MARK != 0x9
    * MARK != 0x2
    * MARK & 0xc0000000 != 0x40000000
    * MARK & 0xc0000000 != 0x80000000
    * MARK & 0x1000000 != 0x1000000

  ```ini
  Format: [Hex number]
  Example: MARK=0x169
  ```
</details>

<details>
  <summary>PREFIX</summary>

  * The prefix that will be used when adding custom iptables chains.
  * If you are running multiple VPN configurations, this needs to be unique in each `vpn.conf`.

  ```ini
  Format: [Prefix]
  Example: PREFIX=VPN_
  ```
</details>

<details>
  <summary>PREF</summary>

  * The preference that will be used when adding the policy-based routing rule.
  * It should preferably be less than the rules Ubiquiti added which can be seen when running `ip rule`.

  ```ini
  Format: [Number]
  Example: PREF=99
  ```
</details>

<details>
  <summary>DEV</summary>

  * The name of the VPN tunnel device to use for openvpn.
  * If you are running multiple VPN configurations, this needs to be unique in each `vpn.conf`.
  * For OpenVPN, this variable needs to be passed to openvpn via the --dev option or openvpn will default to tun0.

  ```ini
  Format: [tunX]
  Example: DEV=tun0
  ```
</details>

<details>
  <summary>hooks_pre_up, hooks_up, hooks_down, hooks_force_down</summary>

  * These functions can be defined in your vpn.conf file and will be called when the VPN is brought down or up. For examples on how to use these hooks, please see the [filled sample](https://github.com/peacey/split-vpn/blob/main/vpn/vpn.conf.filled.sample).
  * There are four hooks that you can use:
    1. The pre-up hook (hooks_pre_up) is called before the VPN connects if you used the pre-up line in your run script.
    2. The up hook (hooks_up) is called after the VPN connects.
    3. The down hook (hooks_down) is called when the VPN disconnects or exits (but not forced down).
    4. The force-down hook (hooks_force_down) is called when the VPN is forced down using the updown.sh force-down command.
</details>
</details>

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. Please see the [LICENSE](https://github.com/peacey/split-vpn/blob/main/LICENSE) for more information.

Contact me at peaceyall AT gmail.com or open an issue on GitHub if you have any questions.
