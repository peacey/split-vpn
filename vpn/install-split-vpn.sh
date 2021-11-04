#!/bin/sh
# This script downloads the latest split-vpn and installs it
# to the data directory (/mnt/data or /data, whichever exists).
set -e

# Get the persistent data directory
if [ -d "/mnt/data" ]; then
	DATA_DIR="/mnt/data"
elif [ -d "/data" ]; then
	DATA_DIR="/data"
else
	echo ERROR: Could not find the data directory.
	exit 1
fi

# Download and install
mkdir -p "${DATA_DIR}/split-vpn"
cd "${DATA_DIR}/split-vpn"
echo Downloading latest split-vpn...
curl -LsSfo split-vpn.zip https://github.com/peacey/split-vpn/archive/main.zip
echo Installing to "${DATA_DIR}/split-vpn"...
unzip -oq split-vpn.zip
cp -rf split-vpn-main/vpn ./
rm -rf split-vpn-main split-vpn.zip
chmod +x vpn/*.sh vpn/hooks/*/*.sh vpn/vpnc-script

# Link to /etc
rm -f /etc/split-vpn
ln -sf "${DATA_DIR}/split-vpn" /etc/split-vpn 

echo split-vpn has been installed to "${DATA_DIR}/split-vpn" and linked to /etc/split-vpn.
