#!/bin/bash

LOGDIRECTORY="$HOME/kubernetesalllogs"
CURRENTUSER=$(whoami)
LOGCOLLECTOUTPUTFILE="log_output.log"

MACHINELIST=""
for ip in 10.240.0.{4..21}; do
  ping -c 1 -W 1 $ip | grep "64 bytes" && MACHINELIST+=" $ip"
done

for ip in 10.240.255.{5..12}; do
  ping -c 1 -W 1 $ip | grep "64 bytes" && MACHINELIST+=" $ip"
done


echo $MACHINELIST


if [ -d "$LOGDIRECTORY" ]; then
    printf "$(date -u) found old logs at $LOGDIRECTORY, removing $LOGDIRECTORY"
    sudo rm -r -f $LOGDIRECTORY
    mkdir -p $LOGDIRECTORY
else
    mkdir -p $LOGDIRECTORY
fi


printf " $(date -u) Start log collection \n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
printf " $(date -u) MACHINELIST $1 \n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE

printf " $(date -u) backup known_hosts\n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts" 
KNOWN_HOSTS_FILE_BACKUP="$LOGDIRECTORY/known_hosts"

if [ -f "$KNOWN_HOSTS_FILE" ]
then
    sudo mv -f "$KNOWN_HOSTS_FILE" "$KNOWN_HOSTS_FILE_BACKUP"
fi

for m in $MACHINELIST
do
    ssh-keyscan $m >> "$KNOWN_HOSTS_FILE"
done

for m in $MACHINELIST
do
    ssh $CURRENTUSER@$m 'bash -s' < collectlogs.sh
done

printf " $(date -u) Copy logs back \n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE

for m in $MACHINELIST
do
    scp -rp $CURRENTUSER@$m:/home/$CURRENTUSER/kuberneteslogs/* $LOGDIRECTORY
    ssh -t $CURRENTUSER@$m "sudo rm -r -f /home/$CURRENTUSER/kuberneteslogs"
done


kubectl cluster-info &> $LOGDIRECTORY/cluster-info.log
kubectl cluster-info dump &> $LOGDIRECTORY/cluster-info-dump.log


if [ -f "$KNOWN_HOSTS_FILE_BACKUP" ]
then
    sudo rm -f "$KNOWN_HOSTS_FILE"
    sudo mv -f "$KNOWN_HOSTS_FILE_BACKUP" "$KNOWN_HOSTS_FILE"
else
    sudo rm -f "$KNOWN_HOSTS_FILE"
fi


LOGZIPFILENAME="$HOSTNAME-KubernetesLogs.tar.gz"

sudo chown -R $CURRENTUSER $LOGDIRECTORY
if [ -f $LOGZIPFILENAME ]
then
    sudo rm -f $LOGZIPFILENAME
fi

sudo tar -czf $LOGZIPFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGZIPFILENAME



printf " $(date -u) restore known_hosts\n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
sudo rm -f "$KNOWN_HOSTS_FILE"

if [ -f "$KNOWN_HOSTS_FILE_BACKUP" ]
then
    sudo mv -f "$KNOWN_HOSTS_FILE_BACKUP" "$KNOWN_HOSTS_FILE"
fi

echo " $(date -u) End log collection \n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
