#!/bin/bash

TMP=$(mktemp -d)
WD="cluster-snapshot"
LOGDIRECTORY=${TMP}/${WD}
mkdir -p ${LOGDIRECTORY}

echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting cluster snapshot"
kubectl cluster-info dump --output-directory ${TMP} &> /dev/null
cp ${TMP}/*.json ${TMP}/kube-system/*.json ${LOGDIRECTORY}

(cd $TMP && zip -q -r ~/${WD}.zip ${WD})
