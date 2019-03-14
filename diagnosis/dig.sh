#!/bin/bash

function download_scripts
{
    ARTIFACTSURL=$1

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Pulling dependencies from this repo: $ARTIFACTSURL"

    mkdir -p scripts

    for script in detectors
    do
        if [ -f scripts/$script.sh ]; then
            echo "[$(date +%Y%m%d%H%M%S)][INFO] Dependency '$script.sh' already in local file system"
        fi

        SCRIPTURL=$ARTIFACTSURL/diagnosis/$script.sh
        curl -fs $SCRIPTURL -o scripts/$script.sh

        if [ ! -f scripts/$script.sh ]; then
            echo "[$(date +%Y%m%d%H%M%S)][ERROR] Required script not available. URL: $SCRIPTURL"
            echo "[$(date +%Y%m%d%H%M%S)][ERROR] You may be running an older version. Download the latest script from github: https://aka.ms/AzsK8sLogCollectorScript"
            exit 1
        fi
    done
}

find_dvm_issues() 
{
    for host in $(ls $LOGDIRECTORY | grep vmd-* | xargs);
    do
        echo "[$(date +%Y%m%d%H%M%S)][INFO][$host] Looking for known issues and misconfigurations"
        find_cse_errors $LOGDIRECTORY/$host/cse/cluster-provision.log 
        find_cse_errors $LOGDIRECTORY/$host/cloud-init-output.log
        find_spn_errors $LOGDIRECTORY/$host/deploy-script-dvm.log
        find_spn_errors $LOGDIRECTORY/$host/acsengine-kubernetes-dvm.log
    done
}

find_node_issues() 
{
    for host in $(ls $LOGDIRECTORY | grep k8s-* | xargs);
    do
        echo "[$(date +%Y%m%d%H%M%S)][INFO][$host] Looking for known issues and misconfigurations"
        find_cse_errors $LOGDIRECTORY/$host/cse/cluster-provision.log 
        find_cse_errors $LOGDIRECTORY/$host/cloud-init-output.log 
        find_etcd_bad_cert_errors $LOGDIRECTORY/$host/cse/cluster-provision.log $LOGDIRECTORY/$host/etcd_status.log
    done
}

# == MAIN ==

if [ "$#" -eq 0 ]; then
    echo ""
    echo "Usage:"    
    echo "  $0 ./KubernetesLogs_%Y-%m-%d-%H-%M-%S-%3N"
    echo ""
    echo "ARTIFACTSURL can be overridden"
    exit 1
fi

LOGDIRECTORY=$1
ERRFILE="$LOGDIRECTORY/ISSUES.txt"

ARTIFACTSURL="${ARTIFACTSURL:-https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master}"
download_scripts $ARTIFACTSURL

source scripts/detectors.sh $ERRFILENAME

find_dvm_issues
find_node_issues
