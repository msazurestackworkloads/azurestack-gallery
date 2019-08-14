#!/bin/bash

###
#   <summary>
#       Find nodes on the network using the `ping` command instead of `kubectl get nodes`.
#       This approach should still give us back results even if the Kubernetes API is having problems.
#   </summary>
###

WD=$1
mkdir -p $WD
TMP=$(mktemp -d)

HOSTLIST=$WD/host.list
rm -f $HOSTLIST

echo "[$(date +%Y%m%d%H%M%S)][INFO] Searching for cluster nodes"
#If the node count increases ip ranges needs to be modified 
for ip in 10.240.0.{4..100};
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done
for ip in 10.240.255.{5..100};
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done

echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting cluster snapshot"
kubectl cluster-info dump --output-directory ${TMP} &> /dev/null
cp ${TMP}/*.json ${TMP}/kube-system/*.json ${WD}

tar -zcf ${WD}.tar.gz ${WD} 
rm -rf ${WD}
