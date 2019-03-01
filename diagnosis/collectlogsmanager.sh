#! /bin/bash

find_hosts() 
{   
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Searching for cluster nodes"
    rm -f $HOSTLIST

    for ip in 10.240.0.{4..21}; do
      ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
    done

    for ip in 10.240.255.{5..12}; do
      ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
    done
}

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="cluster-$NOW"
LOGFILENAME="cluster_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/cluster_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`
HOSTLIST=$LOGDIRECTORY/hosts.list

# Download scripts
ARTIFACTSURL="https://raw.githubusercontent.com/jadarsie/azurestack-gallery/log-collector"
curl -O $ARTIFACTSURL/diagnosis/common.sh;
sudo chmod 744 common.sh
curl -O $ARTIFACTSURL/diagnosis/collectlogs.sh;
sudo chmod 744 collectlogs.sh

echo "[$(date +%Y%m%d%H%M%S)][INFO] Cleaning up cluster temp files"
sudo rm -f cluster_logs.tar.gz
sudo rm -r -f cluster-*

mkdir $LOGDIRECTORY

echo "[$(date +%Y%m%d%H%M%S)][INFO] Starting log collection orchestration"

# Backup known_hosts file
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts" 
KNOWN_HOSTS_FILE_BACKUP="$KNOWN_HOSTS_FILE.bak" 

if [ -f "$KNOWN_HOSTS_FILE" ]
then
    echo "[$(date +%Y%m%d%H%M%S)] Backing up known_hosts file"
    sudo cp $KNOWN_HOSTS_FILE $KNOWN_HOSTS_FILE_BACKUP
fi

find_hosts

for host in $(cat $HOSTLIST); do
    # Adding keys to known_hosts
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Adding $host to known_hosts"
    ssh-keyscan $host >> $KNOWN_HOSTS_FILE
    
    # Collect node logs
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Executing log collection process from $host"
    scp -q common.sh $CURRENTUSER@$host:/home/$CURRENTUSER/common.sh
    ssh $CURRENTUSER@$host "sudo chmod 744 common.sh;"
    scp -q collectlogs.sh $CURRENTUSER@$host:/home/$CURRENTUSER/collectlogs.sh
    ssh $CURRENTUSER@$host "sudo chmod 744 collectlogs.sh; ./collectlogs.sh"

    # Download logs
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs from $host"
    scp -q $CURRENTUSER@$host:/home/$CURRENTUSER/kube_logs.tar.gz $LOGDIRECTORY/kube_logs.tar.gz
    ssh $CURRENTUSER@$host "if [ -f kube_logs.tar.gz ]; then sudo rm -f kube_logs.tar.gz; fi;"
    tar -xzf $LOGDIRECTORY/kube_logs.tar.gz -C $LOGDIRECTORY
    rm -f $LOGDIRECTORY/kube_logs.tar.gz

    # Clean up node
    ssh -q $CURRENTUSER@$host "if [ -f common.sh ]; then sudo rm -f common.sh; fi;"
    ssh -q $CURRENTUSER@$host "if [ -f collectlogs.sh ]; then sudo rm -f collectlogs.sh; fi;"
done

# Collect cluster logs
echo "[$(date +%Y%m%d%H%M%S)][INFO] Dumping cluster-info"    
kubectl cluster-info &> $LOGDIRECTORY/cluster-info.log
kubectl cluster-info dump &> $LOGDIRECTORY/cluster-info-dump.log


# Restore known_hosts file
echo "[$(date +%Y%m%d%H%M%S)][INFO] Restoring known_hosts file"
if [ -f "$KNOWN_HOSTS_FILE_BACKUP" ]
then
    sudo rm -f "$KNOWN_HOSTS_FILE"
    sudo mv -f "$KNOWN_HOSTS_FILE_BACKUP" "$KNOWN_HOSTS_FILE"
else
    sudo rm -f "$KNOWN_HOSTS_FILE"
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Compressing logs into $LOGFILENAME"
rm -f $HOSTLIST
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO] Cleaning up"
sudo rm -r -f $LOGDIRECTORY
