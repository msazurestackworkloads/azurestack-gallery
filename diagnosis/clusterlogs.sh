#!/bin/bash

#source ./common.sh

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
        -n|--namespaces)
            NAMESPACES="$2"
            shift 2
        ;;
        -s|--scripts-folder)
            SCRIPTS_FOLDER="$2"
            shift 2
        ;;
        *)
            echo ""
            echo -e "$(date) [Err] Incorrect option $1"
            exit 1
        ;;
    esac
done


if [[ -z $USER_NAME ]];
then
    echo -e "$(date) [Err] Username not set"
    exit 1
fi

if [[ -z $HOST_LIST ]];
then
    echo -e "$(date) [Err] host list not set"
    exit 1
fi

if [[ ! -d $OUTPUT_FOLDER ]];
then
    echo -e "$(date) [Err] output directory does not exist"
    exit 1
fi

if [[ -z $NAMESPACES ]];
then
    echo -e "$(date) [Err] namespaces not set"
    exit 1
fi

if [[ ! -d $SCRIPTS_FOLDER ]];
then
    echo -e "$(date) [Err] scripts folder does not exist"
    exit 1
fi

source $SCRIPTS_FOLDER/common.sh $OUTPUT_FOLDER "clusterlogs"
source ./defaults.env

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "HOST_LIST: $HOST_LIST"
log_level -i "JOURNALCTL_MAX_LINES: $JOURNALCTL_MAX_LINES"
log_level -i "NAMESPACES: $NAMESPACES"
log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
log_level -i "SCRIPTS_FOLDER: $SCRIPTS_FOLDER"
log_level -i "USER_NAME: $USER_NAME"
log_level -i "-----------------------------------------------------------------------------"



##############################################################
# Creating log folder

TEMP_DIR="/home/$USER_NAME/cluster-logs"
for IP in $HOST_LIST
do
    ssh -q -t $USER_NAME@$IP "mkdir -p $TEMP_DIR"
done


# ##############################################################
# # Collecting waagent tree

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    log_level -i "Collecting waagent tree from [$HOST_NAME]"
    
    WAAGENT_DIR="/var/lib/waagent"
    WAAGENT_FN="$(basename $WAAGENT_DIR).tree"
    
    log_level -i "Checking if [$WAAGENT_DIR] directory is available"
    DIRECTORY_TEST=$(ssh -q -t $USER_NAME@$IP "if [[ -d $WAAGENT_DIR ]]; then echo 'Exits'; fi")
    
    if [[ $DIRECTORY_TEST == "Exits" ]]; then
        EXPORT_STATUS=$(ssh -q -t $USER_NAME@$IP "if sudo find $WAAGENT_DIR &> $TEMP_DIR/$WAAGENT_FN; then echo 'exported'; fi")
        if [[ $EXPORT_STATUS == "exported" ]]; then
            log_level -i "Tree copy successful"
        else
            log_level -e "Tree copy failed [$EXPORT_STATUS]"
        fi
    else
        log_level -e "Directory [$WAAGENT_DIR] does not exist"
    fi
done


# ##############################################################
# # Collecting cluster logs

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    log_level -i "Collecting log files from [$HOST_NAME]"
    
    LOG_PATHS="/var/log/cloud-init.log /var/log/cloud-init-output.log /var/log/syslog /opt/m"
    
    for LOGFILE in $LOG_PATHS
    do
        log_level -i "Checking if [$LOGFILE] exist on [$HOST_NAME]"
        FILE_TEST=$(ssh -q -t $USER_NAME@$IP "if [[ -f $LOGFILE ]]; then echo 'Exits'; fi")
        
        if [[ $FILE_TEST == "Exits" ]]; then
            EXPORT_STATUS=$(ssh -q -t $USER_NAME@$IP "if sudo cp $LOGFILE $TEMP_DIR; then echo 'exported'; fi")
            if [[ $EXPORT_STATUS == "exported" ]]; then
                log_level -i "File copy successful"
            else
                log_level -e "File copy failed [$EXPORT_STATUS]"
            fi
        else
            log_level -e "File [$LOGFILE] does not exist"
        fi
    done
done


# ##############################################################
# # Collecting cluster log directories

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    log_level -i "Collecting log directories from [$HOST_NAME]"
    
    LOG_PATHS="/var/log/azure /var/log/apt /etc/kubernetes/manifests"
    
    for LOGDIR in $LOG_PATHS
    do
        log_level -i "Checking if [$LOGDIR] exist on [$HOST_NAME]"
        FILE_TEST=$(ssh -q -t $USER_NAME@$IP "if [[ -d $LOGDIR ]]; then echo 'exits'; fi")
        
        if [[ $FILE_TEST == "exits" ]]; then
            EXPORT_STATUS=$(ssh -q -t $USER_NAME@$IP "if sudo cp -r $LOGDIR $TEMP_DIR; then echo 'exported'; fi")
            if [[ $EXPORT_STATUS == "exported" ]]; then
                log_level -i "Directory copy successful"
            else
                log_level -e "Directory copy failed [$EXPORT_STATUS]"
            fi
        else
            log_level -e "Directory [$LOGDIR] does not exist"
        fi
    done
done

# ##############################################################
# # Exporting Container list

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    log_level -i "Exporting Container list from [$HOST_NAME]"
    
    EXPORT_STATUS=$(ssh -q -t $USER_NAME@$IP "if sudo docker ps &> $TEMP_DIR/containers.list; then echo 'exported'; fi")
    
    if [[ $EXPORT_STATUS == "exported" ]]; then
        log_level -i "Container list export complete"
    else
        log_level -e "Container list export failed [$EXPORT_STATUS]"
    fi
    
done

##############################################################
# Collecting pod logs within specified namespace

log_level -i "Creating Pod list"
POD_LIST=""
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    if [[ $HOST_NAME == *"master"* ]]; then
        #create list of containers
        if [[ $NAMESPACES != "all" ]]; then
            log_level -i "Getting namespaces from list"
            for NAMESPACE in $NAMESPACES
            do
                log_level -i "Getting pods from [$NAMESPACE]"
                ssh -q -t $USER_NAME@$IP "kubectl get pods -n $NAMESPACE -o custom-columns=NAME:.metadata.name --no-headers >> $TEMP_DIR/pods.list"
            done
            POD_LIST=$(ssh -q -t $USER_NAME@$IP "POD=\$(cat $TEMP_DIR/pods.list); echo \$POD")
        else
            log_level -i "Getting all namespaces"
            ssh -q -t $USER_NAME@$IP "kubectl get pods --all-namespaces -o custom-columns=NAME:.metadata.name --no-headers &> $TEMP_DIR/pods.list"
            POD_LIST=$(ssh -q -t $USER_NAME@$IP "POD=\$(cat $TEMP_DIR/pods.list); echo \$POD")
        fi
    fi
done

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Getting container logs within the namespace [$NAMESPACES] on the host [$HOST_NAME]"
    CONTAINER_DIRECTORY=$(ssh -q -t $USER_NAME@$IP "list=\$(ls /var/log/containers/); echo \$list")
    
    ssh -q -t $USER_NAME@$IP "mkdir -p $TEMP_DIR/containers/"
    
    for FILE in $CONTAINER_DIRECTORY
    do
        FILENAME=$(ssh -q -t $USER_NAME@$IP "IFS='_'; read -ra FORMATTED_FILENAME <<< $FILE; echo \$FORMATTED_FILENAME")
        log_level -i "Current File $FILENAME"
        COPY_STATUS=$(ssh -q -t $USER_NAME@$IP "if [[ '$POD_LIST' == *'$FILENAME'* ]]; then echo 'true'; fi")
        log_level -i "Current copy status $COPY_STATUS"
        
        if [[ $COPY_STATUS == "true" ]]; then
            log_level -i "Copying current File $FILE"
            
            EXPORT_STATUS=$(ssh -q -t $USER_NAME@$IP "if sudo cp /var/log/containers/$FILE $TEMP_DIR/containers/; then echo 'exported'; fi")
            if [[ $EXPORT_STATUS == "exported" ]]; then
                log_level -i "File copy successful"
            else
                log_level -e "File copy failed [$EXPORT_STATUS]"
            fi
            
        fi
    done
    
done


# ##############################################################
# # Exporting Kubectl infromation

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    if [[ $HOST_NAME == *"master"* ]]; then
        ssh -q -t $USER_NAME@$IP "mkdir -p $TEMP_DIR/kubectl/"
        log_level -i "Exporting Kubectl infromation [$HOST_NAME]"
        ssh -q -t $USER_NAME@$IP "kubectl version &> $TEMP_DIR/kubectl/kube-version.log"
        ssh -q -t $USER_NAME@$IP "kubectl cluster-info &> $TEMP_DIR/kubectl/cluster-info.log"
        ssh -q -t $USER_NAME@$IP "kubectl cluster-info dump &> $TEMP_DIR/kubectl/cluster-info-dump.log"
        
        if [[ $NAMESPACES != "all" ]]; then
            for NAMESPACE in $NAMESPACES
            do
                log_level -i "Exporting Kubectl infromation events from [$NAMESPACE]"
                ssh -q -t $USER_NAME@$IP "kubectl get events -n $NAMESPACE &> $TEMP_DIR/kubectl/$NAMESPACE.events"
            done
        else
            ssh -q -t $USER_NAME@$IP "kubectl get events -n kube-system &> $TEMP_DIR/kubectl/kube-system.events"
        fi
    fi
    
done

# ##############################################################
# # Exporting journalctl logs

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    ssh -q -t $USER_NAME@$IP "mkdir -p $TEMP_DIR/journalctl/"
    
    log_level -i "Exporting journalclt logs from [$HOST_NAME]"
    
    if [[ $HOST_NAME == *"master"* ]]; then
        SERVICES="docker kubelet etcd"
    else
        SERVICES="docker kubelet"
    fi
    
    for SERVICE in $SERVICES
    do
        
        # check if services is installed
        SERVICE_STATUS=$(ssh -q -t $USER_NAME@$IP "if systemctl list-units | grep -q $SERVICE.service; then echo 'exists' fi")
        
        if [[ $SERVICE_STATUS != "exists" ]]; then
            log_level -i "Service [$SERVICE] exists, collecting logs"
            log_level -i "Collecting service status logs"
            ssh -q -t $USER_NAME@$IP "sudo systemctl show $SERVICE &> $TEMP_DIR/journalctl/${SERVICE}_status.log"
            
            log_level -i "Collecting [$SERVICE] journalctl head logs"
            ssh -q -t $USER_NAME@$IP "sudo journalctl -u $SERVICE | head -n $JOURNALCTL_MAX_LINES &> $TEMP_DIR/journalctl/${SERVICE}_journal_head.log"
            
            log_level -i "Collecting [$SERVICE] journalctl tail logs"
            ssh -q -t $USER_NAME@$IP "sudo journalctl -u $SERVICE | tail -n $JOURNALCTL_MAX_LINES &> $TEMP_DIR/journalctl/${SERVICE}_journal_tail.log"
            
            SERVICE_IS_ACTIVE=$(ssh -q -t $USER_NAME@$IP "if systemctl is-active --quiet $SERVICE.service | grep inactive; then echo 'inactive'")
            
            if [[ $SERVICE_IS_ACTIVE == "inactive" ]]; then
                log_level -e " Service [$SERVICE] is inactive"
            fi
        else
            log_level -e " Service [$SERVICE] does not exist"
        fi
    done
done



##############################################################
# Copying Logs to local and deleting temporary folder location

for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Copying Logs from [$HOST_NAME]"
    ssh -q -t $USER_NAME@$IP "sudo chmod -R a+r $TEMP_DIR"
    scp -q -r $USER@$IP:"$TEMP_DIR" $OUTPUT_FOLDER/$HOST_NAME
    
    log_level -i "Deleting Temporary Directory"
    ssh -q -t $USER_NAME@$IP "sudo rm -rf $TEMP_DIR"
done