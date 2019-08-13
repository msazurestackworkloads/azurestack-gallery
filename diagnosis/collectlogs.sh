#!/bin/bash

collectKubeletMetadata()
{
    TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)
    KUBELET_IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep hyperkube)
    KUBELET_VERBOSITY=$(cat /etc/systemd/system/kubelet.service | grep -e '--v=[0-9]' -oh | grep -e [0-9] -oh | head -n 1)
    KUBELET_LOG_FILE=$LOGDIRECTORY/daemons/kubelet-${HOSTNAME}.log
    
    echo "== BEGIN HEADER =="               > ${KUBELET_LOG_FILE}
    echo "Type: Daemon"                     >> ${KUBELET_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${KUBELET_LOG_FILE}
    echo "Name: kubelet"                    >> ${KUBELET_LOG_FILE}
    echo "Image: ${KUBELET_IMAGE}"          >> ${KUBELET_LOG_FILE}
    echo "Verbosity: ${KUBELET_VERBOSITY}"  >> ${KUBELET_LOG_FILE}
    echo "== END HEADER =="                 >> ${KUBELET_LOG_FILE}
}

NOW=`date +%Y%m%d%H%M%S`
CURRENTUSER=`whoami`

LOGDIRECTORY="$HOSTNAME-$NOW"
mkdir -p $LOGDIRECTORY

LOGFILENAME="kube_logs.tar.gz"
sudo rm -f $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting /var/log/azure logs"
mkdir -p $LOGDIRECTORY/var/log/azure
sudo cp /var/log/azure/*.log $LOGDIRECTORY/var/log/azure || :
sudo cp /var/log/waagent.log $LOGDIRECTORY/var/log || :

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting static pods manifests"
mkdir -p $LOGDIRECTORY/etc/kubernetes/manifests
sudo cp /etc/kubernetes/manifests/* $LOGDIRECTORY/etc/kubernetes/manifests 2>/dev/null

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in all namespaces"
test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in these namespaces: $NAMESPACES"
mkdir -p $LOGDIRECTORY/containers

for cid in $(docker ps -a -q --no-trunc)
do
    cns=`docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.namespace" }}' $cid`
    
    # if NAMESPACES not set, then collect everything
    if [ -z "${NAMESPACES}" ] || (echo $NAMESPACES | grep -qw $cns);
    then
        # Ignore the pod's Pause container
        if docker inspect --format='{{ .Config.Image }}' $cid | grep -q -v pause-amd64;
        then
            # TODO Check size
            cname=`docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.name" }}' $cid`
            clog=`docker inspect --format='{{ .LogPath }}' $cid`
            sudo docker inspect $cid &> $LOGDIRECTORY/containers/$cname.json
            sudo cp $clog $LOGDIRECTORY/containers/$cname.log
        fi
    fi
done

test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting daemon logs"
mkdir -p $LOGDIRECTORY/daemons
collectKubeletMetadata

for service in docker kubelet etcd
do
    if systemctl list-units | grep -q $service.service; then
        # TODO use --until --since --lines to limit size
        sudo journalctl -n 10000 --utc -o short-iso -u $service &>> $LOGDIRECTORY/daemons/${service}-${HOSTNAME}.log
    fi
done

sync

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs and cleaning up temp files"
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME
sudo rm -rf $LOGDIRECTORY
