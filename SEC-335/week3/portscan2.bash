#!/bin/bash

# check args
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <network-prefix> <port>"
    exit 1
fi

network_prefix=$1
port=$2

echo "host,port"

# scan
nmap -p $port "${network_prefix}.0/24" --open -oG - | awk '/Ports:/{print $2"," $5}' | cut -d "/" -f1
