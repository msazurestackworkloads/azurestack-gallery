#!/bin/bash

source ./common.sh

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -u|--user)
            USER_NAME="$2"
            shift 2
        ;;
        -h|--host-list)
            HOST_LIST="$2"
            shift 2
        ;;
        -o|--output-folder)
            OUTPUT_FOLDER="$2"
            shift 2
        ;;
        -d|--dvm-host)
            DVM_HOST="$2"
            shift 2
        ;;
        *)
            echo ""
            log_level -e "[ERR] Incorrect option $1"
            exit 1
        ;;
    esac
done


if [[ -z $USER_NAME ]];
then
    log_level -e "Username not set"
    exit 1
fi

if [[ ! -d $OUTPUT_FOLDER ]];
then
    log_level -e "output directory does not exist"
    exit 1
fi

if [[ -z $DVM_HOST ]];
then
    log_level -e "dvm host not set"
    exit 1
fi

source ./common.sh $OUTPUT_FOLDER "dvmlogs"

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "USER_NAME: $USER_NAME"
log_level -i "DVM_HOST: $DVM_HOST"
log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
log_level -i "-----------------------------------------------------------------------------"


##############################################################
# Creating log folder

TEMP_DIR="/home/$USER_NAME/dvm-logs"
ssh -q -t $USER_NAME@$DVM_HOST "mkdir -p $TEMP_DIR"

HOST_NAME=$(ssh -q -t $USER_NAME@$DVM_HOST 'echo "$(hostname)"')

# ##############################################################
# # Collecting waagent tree

log_level -i "Collecting waagent tree"

WAAGENT_DIR="/var/lib/waagent"
WAAGENT_FN="$(basename $WAAGENT_DIR).tree"

log_level -i "Checking if [$WAAGENT_DIR] directory is available"
DIRECTORY_TEST=$(ssh -q -t $USER_NAME@$DVM_HOST "if [[ -d $WAAGENT_DIR ]]; then echo 'Exits'; fi")

if [[ $DIRECTORY_TEST == "Exits" ]]; then
    EXPORT_STATUS=$(ssh -q -t $USER_NAME@$DVM_HOST "if sudo find $WAAGENT_DIR &> $TEMP_DIR/$WAAGENT_FN; then echo 'exported'; fi")
    if [[ $EXPORT_STATUS == "exported" ]]; then
        log_level -i "Tree copy successful"
    else
        log_level -e "Tree copy failed [$EXPORT_STATUS]"
    fi
else
    log_level -e "Directory [$WAAGENT_DIR] does not exist"
fi

# ##############################################################
# # Collecting journalctl logs

log_level -i "Collecting journalctl logs"

EXPORT_STATUS=$(ssh -q -t $USER_NAME@$DVM_HOST "if sudo journalctl &> $TEMP_DIR/journalctl.log; then echo 'exported'; fi")
if [[ $EXPORT_STATUS == "exported" ]]; then
    log_level -i "Journal log successful"
else
    log_level -e "Journalctl export failed [$EXPORT_STATUS]"
fi

# ##############################################################
# # Collecting cluster logs

log_level -i "Collecting log files from [$HOST_NAME]"

LOG_PATHS="/var/log/cloud-init.log /var/log/cloud-init-output.log /var/log/syslog"

for LOGFILE in $LOG_PATHS
do
    log_level -i "Checking if [$LOGFILE] exist on [$HOST_NAME]"
    FILE_TEST=$(ssh -q -t $USER_NAME@$DVM_HOST "if [[ -f $LOGFILE ]]; then echo 'Exits'; fi")
    
    if [[ $FILE_TEST == "Exits" ]]; then
        EXPORT_STATUS=$(ssh -q -t $USER_NAME@$DVM_HOST "if sudo cp $LOGFILE $TEMP_DIR; then echo 'exported'; fi")
        if [[ $EXPORT_STATUS == "exported" ]]; then
            log_level -i "File copy successful"
        else
            log_level -e "File copy failed [$EXPORT_STATUS]"
        fi
    else
        log_level -e "File [$LOGFILE] does not exist"
    fi
done

# ##############################################################
# # Collecting cluster log directories

log_level -i "Collecting log directories from [$HOST_NAME]"

LOG_PATHS="/var/log/azure /var/log/apt"

for LOGDIR in $LOG_PATHS
do
    log_level -i "Checking if [$LOGDIR] exist on [$HOST_NAME]"
    FILE_TEST=$(ssh -q -t $USER_NAME@$DVM_HOST "if [[ -d $LOGDIR ]]; then echo 'Exits'; fi")
    
    if [[ $FILE_TEST == "Exits" ]]; then
        EXPORT_STATUS=$(ssh -q -t $USER_NAME@$DVM_HOST "if sudo cp -r $LOGDIR $TEMP_DIR; then echo 'exported'; fi")
        if [[ $EXPORT_STATUS == "exported" ]]; then
            log_level -i "Directory copy successful"
        else
            log_level -e "Directory copy failed [$EXPORT_STATUS]"
        fi
    else
        log_level -e "Directory [$LOGDIR] does not exist"
    fi
done



##############################################################
# Copying Logs to local and deleting temporary folder location

log_level -i "Copying Logs"
ssh -q -t $USER_NAME@$DVM_HOST "sudo chmod -R a+r $TEMP_DIR"
scp -q -r $USER@$DVM_HOST:"$TEMP_DIR" $OUTPUT_FOLDER/$HOST_NAME

log_level -i "Deleting Temporary Directory"
ssh -q -t $USER_NAME@$DVM_HOST "sudo rm -rf $TEMP_DIR"