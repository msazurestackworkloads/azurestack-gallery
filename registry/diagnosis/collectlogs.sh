#!/bin/bash

compressLogsDirectory()
{
    sync
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Compressing logs and cleaning up temp files"
    CURRENTUSER=$(whoami)
    LOGFILENAME="${FILENAME}.zip"
    sudo rm -f ${LOGFILENAME}
    
    sudo chown -R ${CURRENTUSER} ${LOGDIRECTORY}
    if [ -f /opt/azure/vhd-install.complete ]; then
        echo "[$(date +%Y%m%d%H%M%S)][INFO] AKS base image; skipping dependencies installation"
    else
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Installing zip package"
        sudo apt install zip -y
    fi
    (cd $TMP && zip -q -r ~/${LOGFILENAME} ${HOSTNAME})
    sudo chown ${CURRENTUSER} ~/${LOGFILENAME}
}

FILENAME=$1
TMP=$(mktemp -d)
LOGDIRECTORY=${TMP}/${HOSTNAME}
echo "[$(date +%Y%m%d%H%M%S)][INFO] Creating log directory (${LOGDIRECTORY})"
mkdir -p ${LOGDIRECTORY}
mkdir -p ${LOGDIRECTORY}/var/log/azure
cd /var/log/azure
for f in *.log
do
    sudo cp "$f" ${LOGDIRECTORY}/var/log/azure/reg-"${f%}" || :
done

#sudo cp /var/log/cloud-init.log ${LOGDIRECTORY}/reg-cloud-init.log || :
#sudo cp /var/log/waagent.log ${LOGDIRECTORY}/reg-waagent.log || :

mkdir -p ${LOGDIRECTORY}/containers
echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting registry container logs."

sudo docker ps -a --no-trunc >> ${LOGDIRECTORY}/containers/containernames.log
sudo sh -c "cp /var/lib/docker/containers/*/*.log ${LOGDIRECTORY}/containers/"

compressLogsDirectory