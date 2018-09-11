#!/bin/bash

LOGDIRECTORY="$HOME/kuberneteslogs/$HOSTNAME"
CURRENTUSER=$(whoami)
LOGCOLLECTOUTPUTFILE="log_output.log"

if [ -d "$LOGDIRECTORY" ]; then
    printf "$(date -u) found old logs at $LOGDIRECTORY, removing $LOGDIRECTORY"
    sudo rm -r -f $LOGDIRECTORY
    mkdir -p $LOGDIRECTORY
else
    mkdir -p $LOGDIRECTORY
fi

printf " $(date -u) Start log collection \n\n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE

printf "$(date -u) Gather linux logs into $LOGDIRECTORY" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE

if [ -d "$LOGDIRECTORY" ]; then
    printf " $(date -u) found old logs at $LOGDIRECTORY, removing $LOGDIRECTORY" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
    sudo rm -r -f $LOGDIRECTORY
    mkdir $LOGDIRECTORY
else
    mkdir $LOGDIRECTORY
fi

SYSLOGPATH="/var/log/syslog"
printf "copying $SYSLOGPATH \n"
sudo cp $SYSLOGPATH $LOGDIRECTORY/

WAAGENTPATH="/var/lib/waagent"
printf "copying $WAAGENTPATH \n"
if [ -d $WAAGENTPATH ]; then
    sudo find $WAAGENTPATH &> $LOGDIRECTORY/"waagentfilelist"
else
    printf " $(date -u) waagent folder $WAAGENTPATH does not exist" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi

WAAGENTLOGPATH="/var/log/waagent.log"
printf "copying $WAAGENTLOGPATH \n"
if [ -f $WAAGENTLOGPATH ]; then
    sudo cp $WAAGENTLOGPATH $LOGDIRECTORY/
else
    printf " $(date -u) can not find waagent log at $WAAGENTLOGPATH " >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi

CLOUDINITLOG="/var/log/cloud-init.log"
printf "copying $CLOUDINITLOG \n"
if [ -f $CLOUDINITLOG ]; then
    sudo cp $CLOUDINITLOG $LOGDIRECTORY/
else
    printf " $(date -u) can not find cloud init log at $CLOUDINITLOG " >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi

MASTERCUSTOMSCRIPTLOG="/var/log/azure"
printf "copying $MASTERCUSTOMSCRIPTLOG \n"
if [ -d $MASTERCUSTOMSCRIPTLOG ]; then
    sudo cp -r $MASTERCUSTOMSCRIPTLOG $LOGDIRECTORY/
else
    printf " $(date -u) can not find master custom log at $MASTERCUSTOMSCRIPTLOG " >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi


ETCDSETUPLOG="/opt/azure/containers/setup-etcd.log"
printf "copying $ETCDSETUPLOG \n"
if [ -f $ETCDSETUPLOG ]; then
    sudo cp $ETCDSETUPLOG $LOGDIRECTORY/
else
    printf " $(date -u) can not find ETCD setup log at $ETCDSETUPLOG " >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi

OPERATIONM="/opt/m"
printf "copying $OPERATIONM \n"
if [ -f $OPERATIONM ]; then
    sudo cp $OPERATIONM $LOGDIRECTORY/
else
    printf " $(date -u) can not find operation log at $OPERATIONM " >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
fi

printf " $(date -u) Getting container instance and logs \n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE

sudo docker ps &> $LOGDIRECTORY/containerList.log
for var in $(docker ps -a -q)
do
    sudo docker logs $var &> $LOGDIRECTORY/$var.log
done

printf "Getting Kubernetes cluster log \n"
sudo journalctl  &> $LOGDIRECTORY/journalctl.log

if systemctl list-units | grep kubelet.service
then
    sudo systemctl status kubelet &> $LOGDIRECTORY/kubeletstatus.log
    sudo journalctl -u kubelet &> $LOGDIRECTORY/kubelet.log
fi

if systemctl list-units | grep etcd.service
then
    sudo systemctl status etcd &> $LOGDIRECTORY/etcdstatus.log
    sudo journalctl -u etcd &> $LOGDIRECTORY/etcd.log
fi

sudo chown -R $CURRENTUSER $LOGDIRECTORY

printf " $(date -u) End log collection \n\n" >> $LOGDIRECTORY/$LOGCOLLECTOUTPUTFILE
