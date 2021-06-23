#!/bin/bash

TMP=$(mktemp -d)
WD="cluster-snapshot"
LOGDIRECTORY=${TMP}/${WD}
mkdir -p ${LOGDIRECTORY}

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] CCollecting cluster snapshot from all namespaces"
test -n "${NAMESPACES}" && NAMESPACES="kube-system${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting cluster snapshot from namespaces: $NAMESPACES"

if [ -z "${NAMESPACES}" ];
then
    kubectl cluster-info dump --all-namespaces --output-directory ${LOGDIRECTORY} &> /dev/null
else
    kubectl cluster-info dump --namespaces "${NAMESPACES}" --output-directory ${LOGDIRECTORY} &> /dev/null
fi

(cd $TMP && zip -q -r ~/${WD}.zip ${WD})
sudo rm -f -r $TMP
