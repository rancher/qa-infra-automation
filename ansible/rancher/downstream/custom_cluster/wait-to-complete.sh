#!/bin/bash

COMPLETED="Tunnel authorizer set Kubelet Port"
TIMEOUT=900  
if timeout "$TIMEOUT" bash -c "journalctl -u rke2-server -f | grep -qF '$COMPLETED'"
then
    exit 0
else
    echo "node did not register properly"
    exit 1
fi
