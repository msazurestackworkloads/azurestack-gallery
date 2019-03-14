#! /bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="dvm_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

# Download scripts
ARTIFACTSURL="https://raw.githubusercontent.com/jadarsie/azurestack-gallery/log-collector"
curl -s -O $ARTIFACTSURL/diagnosis/common.sh;
sudo chmod 744 common.sh

mkdir $LOGDIRECTORY

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up old temp files" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

# Loading common functions
source ./common.sh $ERRFILENAME
source ./detectors.sh $ERRFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Starting DVM log collection" | tee -a $TRACEFILENAME

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

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for Gallery Item deployment log file" | tee -a $TRACEFILENAME
try_copy_file /var/log/azure/acsengine-kubernetes-dvm.log $LOGDIRECTORY/

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Dumping system journal" | tee -a $TRACEFILENAME
sudo journalctl &> $LOGDIRECTORY/journalctl.log

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Looking for known issues and misconfigurations" | tee -a $TRACEFILENAME
find_cse_errors $LOGDIRECTORY/cse/cluster-provision.log 
find_cse_errors $LOGDIRECTORY/cloud-init-output.log
find_spn_errors $LOGDIRECTORY/deploy-script-dvm.log
# This line goes away after gallery item v0.4.1 is available 
find_spn_errors $LOGDIRECTORY/acsengine-kubernetes-dvm.log

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs into $LOGFILENAME" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Cleaning up temp files"
sudo rm -r -f $LOGDIRECTORY