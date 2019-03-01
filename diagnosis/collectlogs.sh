#! /bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="kube_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

if [[ $HOSTNAME == k8s-master* ]]; then ISMASTER=true; else ISMASTER=false; fi

mkdir $LOGDIRECTORY

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up old temp logs" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

# Loading common functions
source ./common.sh $ERRFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Starting log collection" | tee -a $TRACEFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for syslog file" | tee -a $TRACEFILENAME
try_copy_file /var/log/syslog $LOGDIRECTORY/

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping Microsoft Azure Linux Agent (waagent) directory tree" | tee -a $TRACEFILENAME
try_print_directory_tree /var/lib/waagent $LOGDIRECTORY/waagent.tree

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for Microsoft Azure Linux Agent (waagent) log file" | tee -a $TRACEFILENAME
try_copy_file /var/log/waagent.log $LOGDIRECTORY/

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for cloud-init log files" | tee -a $TRACEFILENAME
try_copy_file /var/log/cloud-init.log $LOGDIRECTORY/
try_copy_file /var/log/cloud-init-output.log $LOGDIRECTORY/

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for CSE directory" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/cse/
try_copy_directory_content /var/log/azure/ $LOGDIRECTORY/cse
try_copy_file /opt/m $LOGDIRECTORY/cse/

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping running container list" | tee -a $TRACEFILENAME
sudo docker ps &> $LOGDIRECTORY/containers.list

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for containers logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/containers/
for cid in $(docker ps -a -q --no-trunc)
do
    sudo docker inspect $cid &> $LOGDIRECTORY/containers/$cid.json
    clog=`docker inspect --format='{{.LogPath}}' $cid`
    sudo cp -f $clog $LOGDIRECTORY/containers/$cid.log
done

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping kubelet service status and journal" | tee -a $TRACEFILENAME
if systemctl list-units | grep -q kubelet.service; then
    sudo systemctl show kubelet &> $LOGDIRECTORY/kubelet_status.log
    sudo journalctl -u kubelet &> $LOGDIRECTORY/kubelet_journal.log

    if systemctl is-active --quiet kubelet.service | grep inactive; then
        echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The kubelet service is not running" | tee -a $ERRFILENAME
    fi
else
    echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The kubelet service is not installed" | tee -a $ERRFILENAME
fi

if [ "$ISMASTER" = true ]; then
    if systemctl list-units | grep -q etcd.service; then
        echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping etcd service status and journal" | tee -a $TRACEFILENAME
        sudo systemctl show etcd &> $LOGDIRECTORY/etcd_status.log
        sudo journalctl -u etcd &> $LOGDIRECTORY/etcd_journal.log

        if systemctl is-active --quiet etcd.service | grep inactive; then
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The etcd service is not running" | tee -a $ERRFILENAME
        fi
    else
        echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The etcd service is not installed" | tee -a $ERRFILENAME        
    fi
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs into $LOGFILENAME" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up temp files"
sudo rm -r -f $LOGDIRECTORY
