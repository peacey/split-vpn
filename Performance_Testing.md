# Performance Testing

## Table of Contents

[1. Test Setup](#test-setup)  
[2. Single & Multi-Stream Throughput](#single--multi-stream-throughput)  
[3. Stress Test Throughput](#stress-test-throughput)  
[4. Throughput of Non-VPN Plus VPN Traffic in Parallel](#throughput-of-non-vpn-plus-vpn-traffic-in-parallel)  
[5. Multiserver Throughput](#multiserver-throughput)  
[6. Ookla Speedtests](#ookla-speedtests)  
[7. Disclaimer](#disclaimer)  

## Test Setup

The test setup consists of a cloud VPS running an iPerf3 server, and a physical computer connected to a UDM Pro as the iPerf3 client.

* The VPS was deployed from Vultr running Debian with 6 cores/12 threads @ 4.0 GHz (Intel E-2286G), 32GB RAM, and a 10Gbps network. The VPS is located in San Jose, CA, US.

* The physical computer is an iMac running Arch Linux, with 2 cores/2 threads @ 2.3 GHz, 8GB RAM (Intel i5-7360U), and connected at 10Gbps to a UDM Pro (via an XG-6-PoE switch connected to the UDM Pro's SFP port). The physical computer is located in Edmonton, AB, Canada.

* The WAN connection on the UDM Pro is a 2.5Gbps symmetric fiber service (TELUS Canada). Hence, 2.5Gbps is the maximum throughput achievable in any of the following tests regardless of the VPN.

* The UDM Pro is running UnifiOS 2.4. These results might not be the same on UnifiOS < 2 due to a different software architecture, or on other, less powerful hardware (such as the UDM base or UDR).

* Mullvad was used as the VPN provider for all tests as they provide 10Gbps VPN servers. The Mullvad VPN server is located in Seattle, US and was picked to be relatively close to the phyiscal computer (1300km from Edmonton, AB). Mullvad's server speeds were first validated by setting up a WireGuard server on the 10Gbps VPS, and running an iPerf3 speed test to the VPS WireGuard endpoint from a VPN-forced client on the UDM Pro. This test showed the same throughput as when Mullvad was used as the WireGuard server, validating that Mullvad servers can use the maximum available bandwidth. 

* split-vpn running on the UDM Pro was used to force traffic through the VPN endpoint for all tests. 

## Single & Multi-Stream Throughput

iPerf3 was used to test the download and upload throughput for a single stream, multiple parallel streams (four), and bidirectional streams (downloading and uploading at the same time). The following table shows the download and upload throughput for each test and VPN type. The throughput is shown as `[download]/[upload]` in Mbps. You can click on any of the throughput numbers to show the raw iperf tests and CPU usage graphs for that datapoint.

|                       | Single Stream | Multiple Streams | Bidirectional |
| :---                  |          ---: |             ---: |          ---: |
| **Control (No VPN)**  | [2570/2560](../media/Throughput%20Tests/Single%20Stream/control_iperf_single_stream.png?raw=true) | [2611/2580](../media/Throughput%20Tests/Multiple%20Streams/control_iperf_multiple_streams.png?raw=true) | [2508/2529](../media/Throughput%20Tests/Bidirectional/control_iperf_bidirectional.png?raw=true) |
| **WireGuard**         | [1024/1250](../media/Throughput%20Tests/Single%20Stream/wg_iperf_single_stream.png?raw=true)      | [913/1054](../media/Throughput%20Tests/Multiple%20Streams/wg_iperf_multiple_streams.png?raw=true) | [800/746](../media/Throughput%20Tests/Bidirectional/wg_iperf_bidirectional.png?raw=true) |
| **OpenVPN**           | [222/297](../media/Throughput%20Tests/Single%20Stream/openvpn_iperf_single_stream.png?raw=true)   | [221/290](../media/Throughput%20Tests/Multiple%20Streams/openvpn_iperf_multiple_streams.png?raw=true) | [204/3](../media/Throughput%20Tests/Bidirectional/openvpn_iperf_bidirectional.png?raw=true) |

As expected, WireGuard outperforms OpenVPN and can even saturate a 1 Gbps connection in both download and upload on the UDM Pro.

## Stress Test Throughput

The following table shows the throughput and average CPU usage after continously uploading or downloading with iPerf3 at maximum bandwidth for 120 seconds. The throughput is shown as `[download]/[upload]` in Mbps. CPU Usage is shown as `[download CPU usage]/[upload CPU usage]` in percent. You can click on any of the throughput numbers to show the raw iperf tests and CPU usage graphs for that datapoint.

|                       | Throughput | Average CPU Usage* |
| :---                  |       ---: |               ---: |
| **Control (No VPN)**  | [2457](../media/Throughput%20Tests/Stress%20Test/control_iperf_stress_rx.png?raw=true)/[2560](../media/Throughput%20Tests/Stress%20Test/control_iperf_stress_tx.png?raw=true) | 34/29 |
| **WireGuard**         | [1024](../media/Throughput%20Tests/Stress%20Test/wg_iperf_stress_rx.png?raw=true)/[1218](../media/Throughput%20Tests/Stress%20Test/wg_iperf_stress_tx.png?raw=true)      | 67/66 |
| **OpenVPN**           | [200](../media/Throughput%20Tests/Stress%20Test/openvpn_iperf_stress_rx.png?raw=true)/[300](../media/Throughput%20Tests/Stress%20Test/openvpn_iperf_stress_tx.png?raw=true) | 36/37 |

<sub>\* Idle CPU Usage is 11%.</sub>

In the stress test, WireGuard outperforms OpenVPN in both download and upload and can continously saturate a 1 Gbps connection for 120 seconds in both directions. However, WireGuard uses significantly more CPU than OpenVPN (67% vs. 34%). This is expected as WireGuard utilizes multiple cores for a single connection, while OpenVPN only uses a single core for the connection (however, cryptographic functions still use multiple cores). 

Note that the CPU usage will be much lower and manageable if you are not saturating the VPN connection completely. These stress tests simply demonstrate the maximum CPU usage that will be used if saturating the VPN connection at maximum bandwidth for an extended period of time.

## Throughput of Non-VPN Plus VPN Traffic in Parallel

To test how much non-VPN traffic the UDM Pro can handle in parallel with VPN traffic, we run two iperf tests at the same time: one to a non-VPN forced destination, and one to a VPN-forced destination.

The following table shows the **download** throughput of a VPN-forced speedtest, and the download/upload throughput of a non-VPN-forced speedtest. The non-VPN-forced speedtest first downloads and then uploads (not in parallel), both while the VPN-forced speedtest is running in **download** mode. The throughput is shown as `[download]/[upload]` in Mbps. CPU Usage is shown as a percentage. `Total Throughput` is the sum of VPN and non-VPN throughputs. You can click on the linked throughputs to see the raw iperf tests (including VPN and non-VPN) and CPU usage graphs for that row.

|                       | VPN Download Throughput | Non-VPN Throughput | Total Throughput | Average CPU Usage* |
|   :---                |                    ---: |               ---: |             ---: |               ---: |
| **WireGuard**         | [916](../media/Throughput%20Tests/VPN%20Plus%20Non-VPN%20Traffic/wg_iperf_vpn_plus_nonvpn_rx.png?raw=true) | 1515/2400 |        2431/2400 | 70 |
| **OpenVPN**           | [140](../media/Throughput%20Tests/VPN%20Plus%20Non-VPN%20Traffic/openvpn_iperf_vpn_plus_nonvpn_rx.png?raw=true) | 2324/2497 |        2464/2497 | 43 |

<sub>\* Idle CPU Usage is 11%.</sub>

The following table shows the **upload** throughput of a VPN-forced speedtest, and the download/upload throughput of a non-VPN-forced speedtest. The non-VPN-forced speedtest first downloads and then uploads (not in parallel), both while the VPN-forced speedtest is running in **upload** mode. 

|                       | VPN Upload Throughput | Non-VPN Throughput | Total Throughput | Average CPU Usage* |
|   :---                |                  ---: |               ---: |             ---: |               ---: |
| **WireGuard**         | [876](../media/Throughput%20Tests/VPN%20Plus%20Non-VPN%20Traffic/wg_iperf_vpn_plus_nonvpn_tx.png?raw=true) | 2560/1700 | 2590/2576 | 75 |
| **OpenVPN**           | [224](../media/Throughput%20Tests/VPN%20Plus%20Non-VPN%20Traffic/openvpn_iperf_vpn_plus_nonvpn_tx.png?raw=true) | 2560/2324 | 2569/2548 | 47 |

<sub>\* Idle CPU Usage is 11%.</sub>

The main takeaway from these tables is that even though the VPN is using the full bandwidth it's able to use on the UDM Pro (1 Gbps for WireGuard), the UDM Pro is still able to saturate the 2.5Gbps WAN connection with non-VPN traffic at the same time (as seen in the `Total Throughput` column adding up to 2.5 Gbps for both download and upload directions). Hence, utilizing the VPN at the full possible bandwidth does not seem to impact non-VPN traffic significantly. 

## Multiserver Throughput

The following graphs* show the throughput achieved when multiple VPN servers are used in parallel (up to 7 multiple servers). iPerf tests are run in parallel, each test forced through a different VPN server. Solid lines are throughput curves (left vertical axis), and dashed lines are CPU usage curves (right vertical axis).

<img width="960" alt="Multiserver Throughput Curves" src="../media/Throughput%20Tests/Multiserver/Multiserver_Throughput_Curves.png?raw=true">

For WireGuard with multiple servers, the download throughput marginally increases from 1000 Mbps to 1200-1400 Mbps, and upload throughput marginally increases from 1200 Mbps to 1600 Mbps. However this comes at the expense of the CPU being completely saturated (~100%) after 3 or more servers are utilizing the full bandwidth. Given that WireGuard is already using multiple cores for only one server, we do not expect performance to be that different when multiple servers or WireGuard connections are used.

For OpenVPN with multiple servers, the download throughput more than doubles from 200 Mbps to 500 Mbps, and upload throughput almost triples from 300 Mbps to 800 Mbps. The maximum throughput is achieved with 5 servers, and the CPU remains at 80-90% without complete saturation. This performance improvement is to be expected given that OpenVPN is a single-core process, so using multiple OpenVPN processes can distribute the load across all CPUs. 

For all cases, the CPU usage increases with an increasing number of servers. Again keep in mind that CPU usage will be much lower if you are using multiple servers that are not utilizing the full available bandwidth. 

<sub>\* Raw data for multiple server tests can be found [here](../media/Throughput%20Tests/Multiserver/).</sub>

## Ookla Speedtests

The following table shows VPN-forced speedtests performed with the Ookla Speedtest.net app, on Ethernet and on WiFi. 

* The WiFi testing device is an S22 Ultra connected with WiFI 6E (6GHz/160 MHz) to a U6-Enterprise access point (2.5 Gbps backhaul to the UDM Pro). The S22 Ultra was only ~5m from the access point with a clear line of sight.
* The Ookla speedtest server used was in the same city as the VPN endpoint (Seattle, US).

Throughput is shown as `[download]/[upload]` in Mbps, and ping times are shown as `[idle ping]/[download ping]/[upload ping]` in milliseconds. You can click any of the throughput numbers to go to the Ookla speedtest result page for that datapoint. 

|                       | Ethernet Throughput | Ethernet Ping | WiFi Throughput | WiFi Ping |
| :---                  |      ---: |      ---: |      ---: |      ---: |
| **Control (No VPN)**  | [2590/2574](https://www.speedtest.net/result/c/9eaaa00b-4831-4251-a16a-e4af517ba850) | 1/10/6 | [1663/1615](https://www.speedtest.net/result/a/8987695085) | 8/26/37 |
| **WireGuard**         | [927/1050](https://www.speedtest.net/result/14206703146) | 23/35/46 | [1011/944](https://www.speedtest.net/result/14208597384) | 29/37/62 |
| **OpenVPN**           | [230/316](https://www.speedtest.net/result/c/17e64384-ed89-4b0b-8cc1-926a044ada89) | 60/650/213 | [248/141](https://www.speedtest.net/result/a/8987686605) | 105/423/110 |

The results show that WireGuard outperforms OpenVPN and can saturate a 1 Gbps connection on Ethernet or WiFi, in both download and upload directions. WireGuard also has the best latency, only increasing from 1ms without any VPN to 23ms when using WireGuard on Ethernet. On the other hand, OpenVPN has a idle latency of 60ms on Ethernet, and very high loaded latency compared to WireGuard. This makes OpenVPN on the UDM Pro not an ideal candidate for lower-latency applications like video conferencing.

Note that WiFi throughput will significantly decrease as you get further away from the access point, especially for higher frequencies like 6GHz.

## Disclaimer

There are many factors that can affect throughput including CPU usage, server distance, and hardware used. These results do not guarantee you will get the same results. These are simply the results I got doing these tests a few times. I also did not take averages of multiple tests, so these tests are not scientifically rigorous nor do they examine what would happen under heavy load. Though, they should serve as a good starting point to what throughput you should expect to get under ideal conditions for different circumstances.
