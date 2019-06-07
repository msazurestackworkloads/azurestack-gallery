#! /bin/bash

NOW=`date +%Y%m%d%H%M%S`
LOGDIRECTORY="$HOSTNAME-$NOW"
LOGFILENAME="dvm_logs.tar.gz"
TRACEFILENAME="$LOGDIRECTORY/collector_trace"
ERRFILENAME="$LOGDIRECTORY/ERRORS.txt"
CURRENTUSER=`whoami`

mkdir $LOGDIRECTORY
log_level -i "[$HOSTNAME] Cleaning up old temp files" | tee -a $TRACEFILENAME
sudo rm -f $LOGFILENAME

# Loading common functions
source ./common.sh $ERRFILENAME
source ./detectors.sh $ERRFILENAME
log_level -i "[$HOSTNAME] Starting DVM log collection" | tee -a $TRACEFILENAME

log_level -i "[$HOSTNAME] Looking for syslog file" | tee -a $TRACEFILENAME
try_copy_file /var/log/syslog $LOGDIRECTORY/

log_level -i "[$HOSTNAME] Dumping Microsoft Azure Linux Agent (waagent) directory tree" | tee -a $TRACEFILENAME
try_print_directory_tree /var/lib/waagent $LOGDIRECTORY/waagent.tree

log_level -i "[$HOSTNAME] Looking for Microsoft Azure Linux Agent (waagent) log file" | tee -a $TRACEFILENAME
try_copy_file /var/log/waagent.log $LOGDIRECTORY/

log_level -i "[$HOSTNAME] Looking for cloud-init log files" | tee -a $TRACEFILENAME
try_copy_file /var/log/cloud-init.log $LOGDIRECTORY/
try_copy_file /var/log/cloud-init-output.log $LOGDIRECTORY/

log_level -i"[$HOSTNAME] Looking for CSE directory" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/cse/
try_copy_directory_content /var/log/azure/ $LOGDIRECTORY/cse

log_level -i "[$HOSTNAME] Looking for apt logs" | tee -a $TRACEFILENAME
mkdir -p $LOGDIRECTORY/apt/
try_copy_directory_content /var/log/apt/ $LOGDIRECTORY/apt

log_level -i "[$HOSTNAME] Dumping system journal" | tee -a $TRACEFILENAME
sudo journalctl &> $LOGDIRECTORY/journalctl.log

log_level -i "[$HOSTNAME] Looking for known issues and misconfigurations" | tee -a $TRACEFILENAME
find_cse_errors $LOGDIRECTORY/cse/cluster-provision.log
find_cse_errors $LOGDIRECTORY/cloud-init-output.log
find_spn_errors $LOGDIRECTORY/deploy-script-dvm.log
# This line goes away after gallery item v0.4.1 is available
find_spn_errors $LOGDIRECTORY/acsengine-kubernetes-dvm.log

log_level -i "[$HOSTNAME] Compressing logs into $LOGFILENAME" | tee -a $TRACEFILENAME
sudo chown -R $CURRENTUSER $LOGDIRECTORY
sudo tar -czf $LOGFILENAME $LOGDIRECTORY
sudo chown $CURRENTUSER $LOGFILENAME

log_level -i "[$HOSTNAME] Cleaning up temp files"
sudo rm -r -f $LOGDIRECTORY