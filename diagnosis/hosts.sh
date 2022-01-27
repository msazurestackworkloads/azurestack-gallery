#!/bin/bash

TMP=$(mktemp -d)
WD="cluster-snapshot"
LOGDIRECTORY=${TMP}/${WD}
mkdir -p ${LOGDIRECTORY}

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting cluster snapshot from all namespaces"
test -n "${NAMESPACES}" && NAMESPACES="kube-system${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting cluster snapshot from namespaces: $NAMESPACES"

if [ -z "${NAMESPACES}" ];
then
    sudo kubectl cluster-info dump --all-namespaces --output-directory ${LOGDIRECTORY} --kubeconfig /etc/kubernetes/admin.conf &> /dev/null
else
    sudo kubectl cluster-info dump --namespaces "${NAMESPACES}" --output-directory ${LOGDIRECTORY} --kubeconfig /etc/kubernetes/admin.conf &> /dev/null
fi

(cd $TMP && sudo zip -q -r ~/${WD}.zip ${WD} && sudo chmod 777 ~/${WD}.zip)
sudo rm -f -r $TMP
