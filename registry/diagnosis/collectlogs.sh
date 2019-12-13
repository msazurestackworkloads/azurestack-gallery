#!/bin/bash

compressLogsDirectory()
{
    sync
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Compressing logs and cleaning up temp files"
    CURRETUSER=$(whoami)
    LOGFILENAME="${FILENAME}.zip"
    sudo rm -f ${LOGFILENAME}
    
    sudo chown -R ${CURRETUSER} ${LOGDIRECTORY}
    if [ -f /opt/azure/vhd-install.complete ]; then
        echo "[$(date +%Y%m%d%H%M%S)][INFO] aks base image; skipping dependencies installation"
    else
        echo "[$(date +%Y%m%d%H%M%S)][INFO] installing zip module"
        sudo apt install zip -y
    fi
    (cd $TMP && zip -q -r ~/${LOGFILENAME} ${HOSTNAME})
    sudo chown ${CURRETUSER} ~/${LOGFILENAME}
}

FILENAME=$1
TMP=$(mktemp -d)
LOGDIRECTORY=${TMP}/${HOSTNAME}
echo "[$(date +%Y%m%d%H%M%S)][INFO] Creating log directory(${LOGDIRECTORY})"
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
echo "[$(date +%Y%m%d%H%M%S)][INFO] Collect registry container logs."
for cid in $(sudo docker ps -a -q --no-trunc)
do
    cname=$(sudo docker inspect --format='{{ index .Config.Labels "com.docker.swarm.task.name" }}' ${cid})
    clog=$(sudo docker inspect --format='{{ .LogPath }}' ${cid})
    
    sudo docker inspect ${cid} &> ${LOGDIRECTORY}/containers/${cname}.json
    sudo cat $clog >> ${LOGDIRECTORY}/containers/${cname}.log
done

compressLogsDirectory