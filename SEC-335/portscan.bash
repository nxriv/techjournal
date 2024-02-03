#!/bin/bash

# check args
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <hostfile> <portfile>"
    exit 1
fi

hostfile=$1
portfile=$2

# check existences

if [ ! -f "$hostfile" ]; then
    echo "Error: Hostfile not found."
    exit 2
fi

echo "host,port,status"

# scan
for host in $(cat $hostfile); do
    for port in $(cat $portfile); do
        timeout 1 bash -c "echo > /dev/tcp/$host/$port" 2>dev/null && status="open" || status="closed"
        echo "$host,$port,$status"
    done
done
