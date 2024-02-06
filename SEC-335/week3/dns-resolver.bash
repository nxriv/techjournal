#!/bin/bash

# check args
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <network_prefix> <dns_server>"
    exit 1
fi

network_prefix=$1
dns_server=$2

for i in $(seq 1 254); do
    ip="${network_prefix}.${i}"
    result=$(nslookup $ip $dns_server 2>/dev/null | grep 'name =')
    if [[ ! -z $result ]]; then
        echo $result
    fi
done
