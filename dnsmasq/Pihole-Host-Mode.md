## How to run pihole in host network mode on the UDM

The instructions below were adapted from the original run-pihole instructions [found here](https://github.com/boostchicken/udm-utilities/tree/master/run-pihole).

1. On your controller, make a network with no DHCP server and give it a VLAN. For this example we are using VLAN 5.
2. Download the `10-dns-host.sh` script into `/mnt/data/on_boot.d`
	```sh
	
	```
3. Edit `/mnt/data/on_boot.d/10-dns-host.sh` and set your desired options.
4. If you previously installed the pihole container, stop it and remove it.
	```sh
	podman stop pihole
	podman rm pihole
	```
5. Give the script executable permissions and run it once. Make sure there are no errors (other than healthchecks).
	```sh
	chmod +x /mnt/data/on_boot.d/10-dns-host.sh
	/mnt/data/on_boot.d/10-dns-host.sh
	```
5. Create the persistent Pi-Hole configuration if you haven't before.
	```sh
	mkdir -p /mnt/data/etc-pihole
	mkdir -p /mnt/data/pihole/etc-dnsmasq.d
	```
6. Create and run the pihole container that uses the host network namespace.
	```sh
	podman run -d --network host --restart always \
		--name pihole \
		-e TZ="America/Los Angeles" \
		-v "/mnt/data/etc-pihole/:/etc/pihole/" \
		-v "/mnt/data/pihole/etc-dnsmasq.d/:/etc/dnsmasq.d/" \
		--dns=127.0.0.1 \
		--dns=1.1.1.1 \
		--dns=8.8.8.8 \
		--hostname pi.hole \
		-e VIRTUAL_HOST="pi.hole" \
		-e PROXY_LOCATION="pi.hole" \
		-e ServerIP="10.0.5.3" \
		-e ServerIPv6="fd62:89a2:fda9:e23::2" \
		-e IPv6="True" \
		-e INTERFACE="br5pi" \
		-e WEB_PORT=81 \
		--cap-add NET_ADMIN \
    	pihole/pihole:latest
	```
	
	1. Change the IPs in the above command to the IPs you defined in `10-dns-host.sh`. You can remove `ServerIPv6` and set `IPv6` to False if you don't want IPv6 support.
	2. The PiHole web server will run on port 81 with the above command. The default configuration in `10-dns-host.sh` will add a DNAT rule from port 81 to port 80 for the pihole IP so that the web server is accessible on port 80. If you want to use a different port than 81, make sure to set `REDIRECT_WEB_PORT` in `10-dns-host.sh` to the same IP as `WEB_PORT` above.
7. If this is your first time setting up pihole, follow the rest of the instructions at [run-pihole](https://github.com/boostchicken/udm-utilities/tree/master/run-pihole) to set the pihole password.
8. Check that pihole is working by visiting http://10.0.5.3 in the browser.
