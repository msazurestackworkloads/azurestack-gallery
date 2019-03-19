#! /bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="kube_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

mkdir -p $LOGDIRECTORY

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up old temp logs" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

# Loading common functions
source ./common.sh $ERRFILENAME
source ./detectors.sh $ERRFILENAME

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

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for apt logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/apt/
try_copy_directory_content /var/log/apt/ $LOGDIRECTORY/apt

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping running container list" | tee -a $TRACEFILENAME
sudo docker ps &> $LOGDIRECTORY/containers.list

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for containers logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/containers/
for cid in $(docker ps -a -q --no-trunc)
do
    # TODO Check size
    cname=`docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.name" }}' $cid`
    clog=`docker inspect --format='{{ .LogPath }}' $cid`

    sudo docker inspect $cid &> $LOGDIRECTORY/containers/$cname.json
    sudo cp -f $clog $LOGDIRECTORY/containers/$cname.log
done

if is_master_node; then SERVICES="docker kubelet etcd"; else SERVICES="docker kubelet"; fi

for service in $SERVICES 
do
    echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping $service service status and journal" | tee -a $TRACEFILENAME
    if systemctl list-units | grep -q $service.service; then
        sudo systemctl show $service &> $LOGDIRECTORY/${service}_status.log
        # journal can be long, do not collect everything
        # TODO make this smarter
        sudo journalctl -u $service | head -n 10000 &> $LOGDIRECTORY/${service}_journal_head.log
        sudo journalctl -u $service | tail -n 10000 &> $LOGDIRECTORY/${service}_journal_tail.log

        if systemctl is-active --quiet $service.service | grep inactive; then
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The $service service is not running" | tee -a $ERRFILENAME
        fi
    else
        echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] The $service service is not installed" | tee -a $ERRFILENAME
    fi
done

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for known issues and misconfigurations" | tee -a $TRACEFILENAME
find_cse_errors $LOGDIRECTORY/cse/cluster-provision.log 
find_cse_errors $LOGDIRECTORY/cloud-init-output.log 
find_etcd_bad_cert_errors $LOGDIRECTORY/cse/cluster-provision.log $LOGDIRECTORY/etcd_status.log

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up temp files"
sudo rm -rf $LOGDIRECTORY
