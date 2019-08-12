#!/bin/bash
restoreAzureCLIVariables()
{
    EXIT_CODE=$?
    #restoring Azure CLI values
    export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=$USER_AZURE_CLI_DISABLE_CONNECTION_VERIFICATION
    export ADAL_PYTHON_SSL_NO_VERIFY=$USER_ADAL_PYTHON_SSL_NO_VERIFY
    exit $EXIT_CODE
}

trap restoreAzureCLIVariables EXIT

checkRequirements()
{
    azureversion=$(az --version)
    if [ $? -eq 0 ]; then
        echo "Found azure-cli version: $azureversion"
    else
        echo "azure-cli is missing. Please install azure-cli from"
        echo "https://docs.microsoft.com/azure-stack/user/azure-stack-version-profiles-azurecli2"
    fi
}

printUsage()
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -m 192.168.102.34 -u azureuser -n default -n monitoring --disable-host-key-checking"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32 --resource-group myresgrp --upload-logs"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -m, --master-host               A master node's public IP or FQDN (host name starts with 'k8s-master-')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -r, --resource-group            Kubernetes cluster resource group"
    echo "  -n, --user-namespace            Collect logs for containers in the passed namespace (kube-system logs are always collected)"
    echo "  --all-namespaces                Collect logs for all containers. Overrides the user-namespace flag"
    echo "  --upload-logs                   Stores the retrieved logs in an Azure Stack storage account"
    echo "  --disable-host-key-checking     Sets SSH StrictHostKeyChecking option to \"no\" while the script executes. Use only when building automation in a save environment."
    echo "  -h, --help                      Print the command usage"
    exit 1
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

NAMESPACES="kube-system"
ALLNAMESPACES=1
STRICT_HOST_KEY_CHECKING="ask"
UPLOAD_LOGS=""

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
            shift 2
        ;;
        -m|--master-host)
            MASTER_HOST="$2"
            shift 2
        ;;
        -d|--vmd-host)
            DVM_HOST="$2"
            shift 2
        ;;
        -u|--user)
            USER="$2"
            shift 2
        ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
        ;;
        -n|--user-namespace)
            NAMESPACES="$NAMESPACES $2"
            shift 2
        ;;
        --all-namespaces)
            ALLNAMESPACES=0
            shift
        ;;
        --upload-logs)
            UPLOAD_LOGS="true"
            shift
        ;;
        --disable-host-key-checking)
            STRICT_HOST_KEY_CHECKING="no"
            shift
        ;;
        -h|--help)
            printUsage
        ;;
        *)
            echo ""
            echo "[ERR] Incorrect option $1"
            printUsage
        ;;
    esac
done

# Validate input
if [ -z "$USER" ]
then
    echo ""
    echo "[ERR] --user is required"
    printUsage
fi

if [ -z "$IDENTITYFILE" ]
then
    echo ""
    echo "[ERR] --identity-file is required"
    printUsage
fi

if [ -z "$DVM_HOST" -a -z "$MASTER_HOST" ]
then
    echo ""
    echo "[ERR] Either --vmd-host or --master-host should be provided"
    printUsage
fi

if [ ! -f $IDENTITYFILE ]
then
    echo ""
    echo "[ERR] identity-file not found at $IDENTITYFILE"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep -q "BEGIN \(RSA\|OPENSSH\) PRIVATE KEY" \
    || { echo "The identity file $IDENTITYFILE is not a RSA Private Key file."; echo "A RSA private key file starts with '-----BEGIN [RSA|OPENSSH] PRIVATE KEY-----''"; exit 1; }
fi

if [ -z "$RESOURCE_GROUP" ]
then
    echo ""
    echo "[ERR] --resource-group should be provided"
    printUsage
    exit 1
fi

test $ALLNAMESPACES -eq 0 && unset NAMESPACES

# Print user input
echo ""
echo "user:                    $USER"
echo "identity-file:           $IDENTITYFILE"
echo "master-host:             $MASTER_HOST"
echo "vmd-host:                $DVM_HOST"
echo "resource-group:          $RESOURCE_GROUP"
echo "upload-logs:             $UPLOAD_LOGS"
echo "namespaces:              ${NAMESPACES:-all}"
echo ""

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
mkdir -p $LOGFILEFOLDER
mkdir -p ~/.ssh

echo "[$(date +%Y%m%d%H%M%S)][INFO] Testing SSH keys"
TEST_HOST="${MASTER_HOST:-$DVM_HOST}"
ssh -q $USER@$TEST_HOST "exit"

if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to the server"
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Aborting log collection process"
    exit 1
fi

#checks if azure-cli is installed
checkRequirements

#get user values of azure-cli variables
USER_AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=$AZURE_CLI_DISABLE_CONNECTION_VERIFICATION
USER_ADAL_PYTHON_SSL_NO_VERIFY=$ADAL_PYTHON_SSL_NO_VERIFY

#workaround for SSL interception
export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1
export ADAL_PYTHON_SSL_NO_VERIFY=1

#Validate resource-group
location=$(az group show -n $RESOURCE_GROUP --query location)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Specified Resource group not found."
    exit 1
fi

#Get the master nodes from the resource group
master_nodes=$(az resource list -g $RESOURCE_GROUP --resource-type "Microsoft.Compute/virtualMachines" --query "[?tags.poolName=='master'].{Name:name}" --output tsv)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Kubernetes master nodes not found in the resource group."
    exit 1
fi

if [ -n "$MASTER_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect cluster logs"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Looking for cluster hosts"
    scp -q hosts.sh $USER@$MASTER_HOST:/home/$USER/hosts.sh
    ssh -tq $USER@$MASTER_HOST "sudo chmod 744 hosts.sh; ./hosts.sh $NOW"
    scp -q $USER@$MASTER_HOST:"/home/$USER/$NOW.tar.gz" $LOGFILEFOLDER/cluster-snapshot.tar.gz
    ssh -tq $USER@$MASTER_HOST "sudo rm -f $NOW.tar.gz hosts.sh"
    tar -xzf $LOGFILEFOLDER/cluster-snapshot.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/cluster-snapshot.tar.gz
    mv $LOGFILEFOLDER/$NOW $LOGFILEFOLDER/cluster-snapshot-$NOW
    
    SSH_FLAGS="-q -t -J ${USER}@${MASTER_HOST} -i ${IDENTITYFILE}"
    SCP_FLAGS="-q -o ProxyJump=${USER}@${MASTER_HOST} -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} -o UserKnownHostsFile=/dev/null -i ${IDENTITYFILE}"
    
    for host in $(cat $LOGFILEFOLDER/host.list)
    do
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host $host"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
        scp ${SCP_FLAGS} common.sh ${USER}@${host}:/home/${USER}/
        scp ${SCP_FLAGS} detectors.sh ${USER}@${host}:/home/${USER}/
        scp ${SCP_FLAGS} collectlogs.sh ${USER}@${host}:/home/${USER}/
        ssh ${SSH_FLAGS} ${USER}@${host} "sudo chmod 744 common.sh detectors.sh collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
        scp ${SCP_FLAGS} ${USER}@${host}:"/home/${USER}/kube_logs.tar.gz" ${LOGFILEFOLDER}/kube_logs.tar.gz
        tar -xzf $LOGFILEFOLDER/kube_logs.tar.gz -C $LOGFILEFOLDER
        rm $LOGFILEFOLDER/kube_logs.tar.gz
        
        # Removing temp files from node
        ssh ${SSH_FLAGS} ${USER}@${host} "rm -f common.sh detectors.sh collectlogs.sh collectlogsdvm.sh kube_logs.tar.gz"
    done
    
    rm $LOGFILEFOLDER/host.list
fi

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect VMD logs"
    SSH_FLAGS="-q -t -i ${IDENTITYFILE}"
    SCP_FLAGS="-q -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} -o UserKnownHostsFile=/dev/null -i ${IDENTITYFILE}"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
    scp ${SCP_FLAGS} common.sh ${USER}@${DVM_HOST}:/home/${USER}/
    scp ${SCP_FLAGS} detectors.sh ${USER}@${DVM_HOST}:/home/${USER}/
    scp ${SCP_FLAGS} collectlogsdvm.sh ${USER}@${DVM_HOST}:/home/${USER}/
    ssh ${SSH_FLAGS} ${USER}@${DVM_HOST}: "sudo chmod 744 common.sh detectors.sh collectlogsdvm.sh; ./collectlogsdvm.sh;"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
    scp ${SCP_FLAGS} ${USER}@${DVM_HOST}:"/home/${USER}/dvm_logs.tar.gz" ${LOGFILEFOLDER}/dvm_logs.tar.gz
    tar -xzf $LOGFILEFOLDER/dvm_logs.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/dvm_logs.tar.gz
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Removing temp files from DVM"
    ssh ${SSH_FLAGS} ${USER}@${DVM_HOST}: "rm -f common.sh detectors.sh collectlogs.sh collectlogsdvm.sh dvm_logs.tar.gz"
fi

# Aggregate ERRORS.txt
if [ `find $LOGFILEFOLDER -name ERRORS.txt | wc -w` -ne "0" ];
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Known issues found. Details: $LOGFILEFOLDER/ALL_ERRORS.txt"
    cat $LOGFILEFOLDER/*/ERRORS.txt &> $LOGFILEFOLDER/ALL_ERRORS.txt
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done collecting Kubernetes logs"
echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"
