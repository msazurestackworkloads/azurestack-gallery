#!/bin/bash

# Runs on the master node
# Check if kubelet is running --all nodes
# Checks if docker is running -- all nodes
# Check if etcd is running -- master node
# Check if kubectl is working and configured correctly
# Check if kube-system containers are running in docker
# Check if node to node communication works
# Check for outboud connectivity

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
        -s|--scripts-folder)
            SCRIPTS_FOLDER="$2"
            shift 2
        ;;
        *)
            echo ""
            echo -e "[Err] Incorrect option $1"
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

if [[ ! -d $SCRIPTS_FOLDER ]];
then
    echo -e "$(date) [Err] scripts folder does not exist"
    exit 1
fi

source $SCRIPTS_FOLDER/common.sh $OUTPUT_FOLDER "clusterhealthcheck"

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "HOST_LIST: $HOST_LIST"
log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
log_level -i "SCRIPTS_FOLDER: $SCRIPTS_FOLDER"
log_level -i "USER_NAME: $USER_NAME"
log_level -i "-----------------------------------------------------------------------------"

# ##############################################################
# Checks if kubelet is running on all nodes

log_level -i "Checking for kubelet running on all nodes in the cluster"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Checking for kubelet running on [$HOST_NAME]"
    KUBELET_STATUS=$(ssh -q -t $USER_NAME@$IP "sudo service kubelet status | grep 'Active'")
    
    if [[ $KUBELET_STATUS == *"active"* ]]; then
        log_level -i "Kubelet is running on [$HOST_NAME]. Kubelet test passed"
    else
        log_level -e "Kubelet is not running on [$HOST_NAME]. Kubelet test failed"
    fi
done

# ##############################################################
# Checks if docker is running on all nodes

log_level -i "Checking for docker running on all nodes in the cluster"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Checking for Docker running on [$HOST_NAME]"
    DOCKER_STATUS=$(ssh -q -t $USER_NAME@$IP "sudo service docker status | grep 'Active'")
    
    if [[ $KUBELET_STATUS == *"active"* ]]; then
        log_level -i "Docker is running on [$HOST_NAME]. Docker test passed"
    else
        log_level -e "Docker is not running on [$HOST_NAME]. Docker test passed"
    fi
done

# ##############################################################
# Check if etcd is running on all nodes

log_level -i "Checking for etcd running on all nodes in the cluster"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Checking for etcd running on [$HOST_NAME]"
    ETCD_STATUS=$(ssh -q -t $USER_NAME@$IP "sudo service etcd status | grep 'Active'")
    
    if [[ $ETCD_STATUS == *"active"* ]]; then
        log_level -i "ETCD is active on [$HOST_NAME]. ETCD test passed"
    else
        log_level -e "ETCD is not active on [$HOST_NAME]. ETCD test passed"
    fi
done

# ##############################################################
# Check if kubectl is installed and configured correctly on master nodes

log_level -i "Checking if Kubectl is installed and configured on master nodes"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "$HOST_NAME"
    
    if [[ $HOST_NAME == *"master"* ]]; then
        log_level -i "Checking for kubectl on [$HOST_NAME]"
        KUBECTL_COMMAND=$(ssh -q -t $USER_NAME@$IP "kubectl get nodes")
        if [[ $KUBECTL_COMMAND == *"NAME"* ]]; then
            log_level -i "Kubectl is installed and configued on master node. Kubectl test passed"
        else
            log_level -e "Kubectl is not installed and configued on master node. Kubectl test failed"
        fi
    else
        log_level -i "Host [$HOST_NAME] is not master, skipping test"
    fi
done

# ##############################################################
# Check if kube-system containers are running in docker on nodes

log_level -i "Checking for kubernetes containers running on nodes"
MASTER_CONTAINERS="kube-scheduler kube-controller kube-apiserver kube-addon-manager"
NODE_CONTAINERS="azure-ip-masq-agent kube-flannel kube-proxy"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    CONTAINER_LIST=$(ssh -q -t $USER_NAME@$IP 'LIST=$(docker container ls --format="{{.Names }}" --filter status="running"); echo $LIST')
    
    if [[ $HOST_NAME == *"master"* ]]; then
        log_level -i "Checking for master node containers"
        for CONTAINER in $MASTER_CONTAINERS
        do
            if [[ $CONTAINER_LIST == *"$CONTAINER"* ]]; then
                log_level -i "$CONTAINER running on [$HOST_NAME]. Test passed"
            else
                log_level -e "$CONTAINER not running on [$HOST_NAME]. Test failed"
            fi
        done
        log_level -i "Checking for agent node containers"
        for CONTAINER in $NODE_CONTAINERS
        do
            if [[ $CONTAINER_LIST == *"$CONTAINER"* ]]; then
                log_level -i "$CONTAINER running on [$HOST_NAME]. Test passed"
            else
                log_level -e "$CONTAINER not running on [$HOST_NAME]. Test failed"
            fi
        done
    else
        log_level -i "Checking for agent node containers"
        for CONTAINER in $NODE_CONTAINERS
        do
            if [[ $CONTAINER_LIST == *"$CONTAINER"* ]]; then
                log_level -i "$CONTAINER running on [$HOST_NAME]. Test passed"
            else
                log_level -e "$CONTAINER not running on [$HOST_NAME]. Test failed"
            fi
        done
    fi
done

# ##############################################################
# Check if node to node communication works

log_level -i "Checking nodes can communicate with other nodes"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    log_level -i "Checking connectivity from [$HOST_NAME] to cluster nodes"
    for CURRENTIP in $HOST_LIST
    do
        if [[ $IP != $CURRENTIP ]]; then
            PING_RESULT=$(ssh -q -t $USER_NAME@$IP "ping -c 1 -W 1 "$CURRENTIP" | grep '64 bytes'")
            if [[ ! -z $PING_RESULT ]]; then
                log_level -i "Connectivity from $HOST_NAME to $CURRENTIP successfull"
            else
                log_level -e "Connectivity from $HOST_NAME to $CURRENTIP failed"
            fi
        fi
    done
done

# ##############################################################
# Checking for outboud connectivity on nodes

log_level -i "Checking if nodes have connection to the internet"
for IP in $HOST_LIST
do
    HOST_NAME=$(ssh -q -t $USER_NAME@$IP 'echo "$(hostname)"')
    
    log_level -i "Checking connectivity from [$HOST_NAME] to internet"
    NET_RESULT=$(ssh -q -t $USER_NAME@$IP 'wget -q --spider http://google.com; if [ $? -eq 0 ]; then echo "Online"; else echo "Offline"; fi')
    if [[ $NET_RESULT == "Online" ]]; then
        log_level -i "[$HOST_NAME] internet internet connectivity test passed"
    else
        log_level -e "[$HOST_NAME] internet internet connectivity test failed"
    fi
done