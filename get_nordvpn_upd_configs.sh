#!/bin/bash
wget https://nordvpn.com/ovpn/
cat index.html | grep udp1194.ovpn | cut -d \" -f2 > configlinklist.txt
rm index.html
mkdir nordvpnconfigs/
xargs wget -P nordvpnconfigs/ < configlinklist.txt