#!/bin/bash

LOGDIRECTORY=~/$1

if [ -d "$LOGDIRECTORY" ]; then
    NOW=`date +%Y%m%d%H%M%S`
    mv $LOGDIRECTORY ${LOGDIRECTORY}-${NOW}
fi

mkdir -p ${LOGDIRECTORY}

#sudo cp /var/log/cloud-init.log ${LOGDIRECTORY}/reg-cloud-init.log || :
#sudo cp /var/log/waagent.log ${LOGDIRECTORY}/reg-waagent.log || :
cd /var/log/azure
for f in *.log
do
    sudo cp "$f" ${LOGDIRECTORY}/reg-"${f%}" || :
done

cd ${LOGDIRECTORY}
for cid in $(sudo docker ps -a -q --no-trunc)
do
    cname=$(sudo docker inspect --format='{{ index .Config.Labels "com.docker.swarm.task.name" }}' ${cid})
    clog=$(sudo docker inspect --format='{{ .LogPath }}' ${cid})
    
    sudo docker inspect ${cid} &> ${LOGDIRECTORY}/${cname}.json
    sudo cat $clog >> ${LOGDIRECTORY}/${cname}.log
done
