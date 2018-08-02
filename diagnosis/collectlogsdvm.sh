#!/bin/bash


LOGDIRECTORY="dvmlogs"
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


DVMCUSTOMSCRIPTLOG="/var/log/azure/acsengine-kubernetes-dvm.log"
if [ -f $DVMCUSTOMSCRIPTLOG ]; then
    sudo cp $DVMCUSTOMSCRIPTLOG $LOGDIRECTORY/
else
    echo "can not find dvm custom log at $DVMCUSTOMSCRIPTLOG "
fi

LOGZIPFILENAME="$HOSTNAME-dvmlog.tar.gz"
sudo rm -f $LOGZIPFILENAME
sudo tar -czf $LOGZIPFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGZIPFILENAME

