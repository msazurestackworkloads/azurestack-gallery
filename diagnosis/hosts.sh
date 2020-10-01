#!/bin/bash

TMP=$(mktemp -d)
WD="cluster-snapshot"
LOGDIRECTORY=${TMP}/${WD}
mkdir -p ${LOGDIRECTORY}

echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting cluster snapshot"
kubectl cluster-info dump --output-directory ${TMP} &> /dev/null
cp ${TMP}/*.json ${TMP}/kube-system/*.json ${LOGDIRECTORY}

(cd $TMP && zip -q -r ~/${WD}.zip ${WD})
sudo rm -f -r $TMP

echo "[$(date +%Y%m%d%H%M%S)][INFO] Getting Linux nodes information"
kubectl get nodes -l kubernetes.io/os=linux -o jsonpath='{.items[*].metadata.name}' > linux_nodes.txt

echo "[$(date +%Y%m%d%H%M%S)][INFO] Getting Windows nodes information"
kubectl get nodes -l kubernetes.io/os=windows -o jsonpath='{.items[*].metadata.name}' > windows_nodes.txt