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

echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting cluster snapshot"
kubectl cluster-info dump --output-directory ${TMP} &> /dev/null
cp ${TMP}/*.json ${TMP}/kube-system/*.json ${WD}

tar -zcf ${WD}.tar.gz ${WD}
rm -rf ${WD}
