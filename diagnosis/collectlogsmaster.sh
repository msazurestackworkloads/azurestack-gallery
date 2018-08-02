#!/bin/bash


LOGDIRECTORY="masterlogs"
CURRENTUSER=`whoami`

echo "Gather linux logs into $LOGDIRECTORY"


if [ -d "$LOGDIRECTORY" ]; then
    echo "found old logs at $LOGDIRECTORY, removing $LOGDIRECTORY"
    sudo rm -r -f $LOGDIRECTORY
    mkdir $LOGDIRECTORY
else
    mkdir $LOGDIRECTORY
fi

echo "copying syslog"
sudo cp /var/log/syslog $LOGDIRECTORY/

echo "Checking waagent folder"

WAAGENTPATH="/var/lib/waagent"
if [ -d $WAAGENTPATH ]; then
    sudo find $WAAGENTPATH &> $LOGDIRECTORY/"waagentfilelist"
else
    echo "waagent folder $WAAGENTPATH does not exist"
fi


WAAGENTLOGPATH="/var/log/waagent.log"
if [ -f $WAAGENTLOGPATH ]; then
    sudo cp $WAAGENTLOGPATH $LOGDIRECTORY/
else
    echo "can not find waagent log at $WAAGENTLOGPATH "
fi


MASTERCUSTOMSCRIPTLOG="/var/log/azure"
if [ -d $MASTERCUSTOMSCRIPTLOG ]; then
    sudo cp -r $MASTERCUSTOMSCRIPTLOG $LOGDIRECTORY/
else
    echo "can not find master custom log at $MASTERCUSTOMSCRIPTLOG "
fi


ETCDSETUPLOG="/opt/azure/containers/setup-etcd.log"
if [ -f $ETCDSETUPLOG ]; then
    sudo cp $ETCDSETUPLOG $LOGDIRECTORY/
else
    echo "can not find ETCD setup log at $ETCDSETUPLOG "
fi


sudo docker ps &> $LOGDIRECTORY/containerList.log
for var in $(docker ps -a -q)
do
    sudo docker logs $var &> $LOGDIRECTORY/$var.log
done

sudo systemctl status kubelet &> $LOGDIRECTORY/kubeletstatus.log
sudo journalctl -u kubelet &> $LOGDIRECTORY/kubelet.log
sudo systemctl status etcd &> $LOGDIRECTORY/etcdstatus.log
sudo journalctl -u etcd &> $LOGDIRECTORY/etcd.log



LOGZIPFILENAME="$HOSTNAME-masterlog.tar.gz"
sudo rm -f $LOGZIPFILENAME
sudo tar -czf $LOGZIPFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGZIPFILENAME

