#! /bin/bash
RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
YELLOW='\033[0;33m'  # For crucial check success
NC='\033[0m'        # No color, back to normal


log_level()
{
    case "$1" in
        -e) echo -e "${RED}$(date) [Err]  " ${@:2}
        ;;
        -w) echo -e "${YELLOW}$(date) [Warn] " ${@:2}
        ;;
        -i) echo -e "${GREEN}$(date) [Info] " ${@:2}
        ;;
        *)  echo -e "${NC}$(date) [Debug] " ${@:2}
        ;;
    esac
}


###
#   <summary>
#       Find nodes on the network using the `ping` command instead of `kubectl get nodes`.
#       This approach should still give us back results even if the Kubernetes API is having problems.
#   </summary>
###

WD=$1
mkdir -p $WD

HOSTLIST=$WD/host.list
rm -f $HOSTLIST

log_level -i "Searching for cluster nodes"

kubectlcmd="$(kubectl get nodes)"

if [[ ! -z "$kubectlcmd" ]]; then
    log_level -i "kubectl test passed collecting node ips"
    kubectl get nodes -o custom-columns=IP:.status.addresses[0].address --no-headers >> $HOSTLIST
    
else
    log_level -w "kubectl failed collecting node IPs using fallback"
    for ip in 10.240.0.{4..21};
    do
        ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
    done
    for ip in 10.240.255.{5..12};
    do
        ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
    done
fi

#find way to do this without kubectl 
log_level -i "Dumping cluster-info"
kubectl version &> $WD/kube-version.log
kubectl cluster-info &> $WD/cluster-info.log
kubectl cluster-info dump &> $WD/cluster-info-dump.log
kubectl get events -n kube-system &> $WD/kube-system.events

cd $WD/ && tar -czf ../cluster-info.$WD . && cd
rm -rf $WD
