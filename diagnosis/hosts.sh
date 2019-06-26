# Collects the IP addresses of the hosts and agent nodes
HOSTLIST=""
KUBECTL_COMMAND=$(kubectl get nodes)
if [[ $KUBECTL_COMMAND == *"NAME"* ]]; then
    HOSTLIST=$(kubectl get nodes -o custom-columns=IP:.status.addresses[0].address --no-headers)
else
    for ip in 10.240.0.{4..21};
    do
        PINGTEST=$(ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1)
        HOSTLIST="$HOSTLIST$PINGTEST"
    done
    for ip in 10.240.255.{5..12};
    do
        PINGTEST=$(ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1)
        HOSTLIST="$HOSTLIST$PINGTEST"
    done
fi

echo $HOSTLIST

