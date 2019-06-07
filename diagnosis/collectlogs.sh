#! /bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="kube_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

mkdir -p $LOGDIRECTORY

log_level -i "[$HOSTNAME] Cleaning up old temp logs" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

# Loading common functions
source ./common.sh $ERRFILENAME
source ./detectors.sh $ERRFILENAME

log_level -i "[$HOSTNAME] Starting log collection" | tee -a $TRACEFILENAME

log_level -i "[$HOSTNAME] Looking for syslog file" | tee -a $TRACEFILENAME
try_copy_file /var/log/syslog $LOGDIRECTORY/

log_level -i "[$HOSTNAME] Dumping Microsoft Azure Linux Agent (waagent) directory tree" | tee -a $TRACEFILENAME
try_print_directory_tree /var/lib/waagent $LOGDIRECTORY/waagent.tree

log_level -i "[$HOSTNAME] Looking for Microsoft Azure Linux Agent (waagent) log file" | tee -a $TRACEFILENAME
try_copy_file /var/log/waagent.log $LOGDIRECTORY/

log_level -i "[$HOSTNAME] Looking for cloud-init log files" | tee -a $TRACEFILENAME
try_copy_file /var/log/cloud-init.log $LOGDIRECTORY/
try_copy_file /var/log/cloud-init-output.log $LOGDIRECTORY/

log_level -i "[$HOSTNAME] Looking for CSE directory" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/cse/
try_copy_directory_content /var/log/azure/ $LOGDIRECTORY/cse
try_copy_file /opt/m $LOGDIRECTORY/cse/

log_level -i "[$HOSTNAME] Looking for apt logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/apt/
try_copy_directory_content /var/log/apt/ $LOGDIRECTORY/apt

log_level -i "[$HOSTNAME] Dumping running container list" | tee -a $TRACEFILENAME
sudo docker ps &> $LOGDIRECTORY/containers.list

log_level -i "[$HOSTNAME] Looking for containers logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/containers/manifests

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && log_level -i "[$HOSTNAME] Collection logs from all namespaces"
test -n "${NAMESPACES}" && log_level -i "[$HOSTNAME] Collection logs from containers in these namespaces: $NAMESPACES."

#collecting pod information 
PODDIR=$(ls /var/log/pods)
log_level -i "[$HOSTNAME] Collecting Pod Logs" | tee -a $TRACEFILENAME
if [[ ! -z $PODDIR ]];
then
    for id in $PODDIR
    do 
        sudo cp -r -L /var/log/pods/$id/ $LOGDIRECTORY/pods/
    done
fi

for cid in $(docker ps -a -q --no-trunc)
do
    cns=`docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.namespace" }}' $cid`
    
    # Only collect logs from requested namespaces
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

if is_master_node;
then
    log_level -i "[$HOSTNAME] Looking for static pod manifests" | tee -a $TRACEFILENAME
    try_copy_directory_content /etc/kubernetes/manifests/ $LOGDIRECTORY/containers/manifests
fi

if is_master_node; then SERVICES="docker kubelet etcd"; else SERVICES="docker kubelet"; fi

for service in $SERVICES
do
    log_level -i "[$HOSTNAME] Dumping $service service status and journal" | tee -a $TRACEFILENAME
    if systemctl list-units | grep -q $service.service; then
        sudo systemctl show $service &> $LOGDIRECTORY/${service}_status.log
        # journal can be long, do not collect everything
        # TODO make this smarter
        sudo journalctl -u $service | head -n 10000 &> $LOGDIRECTORY/${service}_journal_head.log
        sudo journalctl -u $service | tail -n 10000 &> $LOGDIRECTORY/${service}_journal_tail.log
        
        if systemctl is-active --quiet $service.service | grep inactive; then
            log_level -e "[$HOSTNAME] The $service service is not running" | tee -a $ERRFILENAME
        fi
    else
        log_level -e "[$HOSTNAME] The $service service is not installed" | tee -a $ERRFILENAME
    fi
done

sync

log_level -i "[$HOSTNAME] Looking for known issues and misconfigurations" | tee -a $TRACEFILENAME
find_cse_errors $LOGDIRECTORY/cse/cluster-provision.log
find_cse_errors $LOGDIRECTORY/cloud-init-output.log
find_etcd_bad_cert_errors $LOGDIRECTORY/cse/cluster-provision.log $LOGDIRECTORY/etcd_status.log

log_level -i "[$HOSTNAME] Compressing logs" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

log_level -i "[$HOSTNAME] Cleaning up temp files"
sudo rm -rf $LOGDIRECTORY
