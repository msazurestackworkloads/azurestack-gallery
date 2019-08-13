#!/bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="kube_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

mkdir -p $LOGDIRECTORY

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up old temp logs" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting /var/log/azure logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/var/log/azure
sudo cp /var/log/azure/*.log $LOGDIRECTORY/var/log/azure || :
sudo cp /var/log/waagent.log $LOGDIRECTORY/var/log || :

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting static pods manifests" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/etc/kubernetes/manifests
sudo cp /etc/kubernetes/manifests/* $LOGDIRECTORY/etc/kubernetes/manifests 2>/dev/null

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in all namespaces"
test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in these namespaces: $NAMESPACES"
mkdir -p $LOGDIRECTORY/containers
mkdir -p $LOGDIRECTORY/daemons

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

for service in docker kubelet etcd
do
    echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting $service service logs" | tee -a $TRACEFILENAME
    if systemctl list-units | grep -q $service.service; then
        # TODO use --until --since --lines to limit size
        sudo journalctl --utc -o short-iso -u $service &> $LOGDIRECTORY/daemons/${service}.service.log
        
        if systemctl is-active --quiet $service.service | grep inactive; then
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] $service service is not running" | tee -a $ERRFILENAME
        fi
    fi
done

sync

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up temp files"
sudo rm -rf $LOGDIRECTORY
