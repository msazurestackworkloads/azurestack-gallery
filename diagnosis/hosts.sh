#! /bin/bash

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

echo "[$(date +%Y%m%d%H%M%S)][INFO] Searching for cluster nodes"
for ip in 10.240.0.{4..21}; 
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done
for ip in 10.240.255.{5..12}; 
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done

echo "[$(date +%Y%m%d%H%M%S)][INFO] Dumping cluster-info"    
kubectl cluster-info &> $WD/cluster-info.log
kubectl cluster-info dump &> $WD/cluster-info-dump.log
kubectl get events --kube-system &> $WD/kube-system.events

cd $WD/ && tar -czf ../cluster-info.$WD . && cd
rm -rf $WD
