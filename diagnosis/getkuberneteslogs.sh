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
    found=2
    if ! command -v az &> /dev/null; then
        found=$((found - 1))
        echo "azure-cli is missing. Please install azure-cli from https://docs.microsoft.com/azure-stack/user/azure-stack-version-profiles-azurecli2"
    fi
    
    if ! command -v jq &> /dev/null; then
        found=$((found - 1))
        echo "jq is missing. Please install jq from https://stedolan.github.io/jq/"
    fi
    
    if [ $found -ne 2 ]; then
        exit 1
    fi
}

copyContainerLogsToSADirectory()
{
    for log in $(ls ${LOGFILEFOLDER}/*/containers/*.log)
    do
        CNAME=$(basename ${log} .log)
        CMETA=${LOGFILEFOLDER}/cluster-snapshot-$NOW/${CNAME}.meta        
        CLOG=${SA_DIR}/${CNAME}.log
        
        echo "== BEGIN HEADER ==" > ${CLOG}
        jq -r 'to_entries|map("\(.key): \(.value|tostring)")|.[]' ${CMETA} >> ${CLOG}
        echo "== END HEADER ==" >> ${CLOG}
        cat ${log} >> ${CLOG}
    done
}

createSADirectories()
{
    local SA_DIR_DATE=$(echo $NOW | head -c 8)
    local SA_DIR_HOUR=$(echo $NOW | tail -c 7 | head -c 2)
    local SA_DIR_MIN=$(echo $NOW | tail -c 5 | head -c 2)
    SA_DIR="${LOGFILEFOLDER}/data/d=${SA_DIR_DATE}/h=${SA_DIR_HOUR}/m=${SA_DIR_MIN}"
    mkdir -p ${SA_DIR}
}

createStorageAccount()
{
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Creating storage account: $SA_NAME"
    az storage account create --name $SA_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --kind Storage --sku Standard_LRS
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error creating storage account: $SA_NAME"
        exit 1
    fi
}

ensureResourceGroup()
{
    if [ $(az group exists --name $SA_RESOURCE_GROUP) = false ]; then
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Creating resource group: $SA_RESOURCE_GROUP"
        az group create -n $SA_RESOURCE_GROUP -l $LOCATION
        if [ $? -ne 0 ]; then
            echo "[$(date +%Y%m%d%H%M%S)][ERR]Error creating resource group: $SA_RESOURCE_GROUP"
            exit 1
        fi
    fi
}

ensureStorageAccount()
{
    #Check if the storage account "kuberneteslogs" is present
    CHECK_STORAGE_ACCOUNT=$(az storage account list -g $SA_RESOURCE_GROUP --output json | jq -r '.[] | select (.name=="'$SA_NAME'")')
    #create storage account "kuberneteslogs" only if not present
    if [ -z "$CHECK_STORAGE_ACCOUNT" ]; then
        createStorageAccount
    fi
}

printUsage()
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -d 192.168.102.34 -g myresgrp -u azureuser -n default -n monitoring --disable-host-key-checking"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32 --resource-group myresgrp"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32 --resource-group myresgrp --upload-logs"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -g, --resource-group            Kubernetes cluster resource group"
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
UPLOAD_LOGS="false"

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
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

SSH_FLAGS="-q -t -i ${IDENTITYFILE}"
SCP_FLAGS="-q -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} -o UserKnownHostsFile=/dev/null -i ${IDENTITYFILE}"

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Testing SSH keys"
    ssh ${SSH_FLAGS} ${USER}@${DVM_HOST} "exit"
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to the server"
        exit 1
    fi
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect VMD logs"
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

#checks if azure-cli is installed
checkRequirements

#get user values of azure-cli variables
USER_AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=$AZURE_CLI_DISABLE_CONNECTION_VERIFICATION
USER_ADAL_PYTHON_SSL_NO_VERIFY=$ADAL_PYTHON_SSL_NO_VERIFY

#workaround for SSL interception
export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1
export ADAL_PYTHON_SSL_NO_VERIFY=1

#Validate resource-group
LOCATION=$(az group show -n $RESOURCE_GROUP --query location 2> /dev/null)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Specified Resource group not found."
    exit 1
fi

#Get the master nodes from the resource group
master_nodes=$(az vm list -g $RESOURCE_GROUP --query "[?tags.poolName=='master'].{Name:name}" --output tsv 2> /dev/null)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Kubernetes master nodes not found in the resource group."
    exit 1
fi

MASTER_IP=$(az network public-ip list -g $RESOURCE_GROUP --output json 2> /dev/null | jq -r '.[] | select (.name | contains("'k8s-master'")) .ipAddress')
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Kubernetes master node ip not found in the resource group."
    exit 1
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Testing SSH keys"
ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "exit"

if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to the server"
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Aborting log collection process"
    exit 1
fi

if [ -n "$MASTER_IP" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect cluster logs"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Looking for cluster hosts"
    scp ${SCP_FLAGS} hosts.sh ${USER}@${MASTER_IP}:/home/${USER}/hosts.sh
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo chmod 744 hosts.sh; ./hosts.sh ${NOW}"
    scp ${SCP_FLAGS} ${USER}@${MASTER_IP}:"/home/${USER}/${NOW}.tar.gz" ${LOGFILEFOLDER}/cluster-snapshot.tar.gz
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo rm -f ${NOW}.tar.gz hosts.sh"
    tar -xzf $LOGFILEFOLDER/cluster-snapshot.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/cluster-snapshot.tar.gz
    mv $LOGFILEFOLDER/$NOW $LOGFILEFOLDER/cluster-snapshot-$NOW
    
    SSH_FLAGS="-q -t -J ${USER}@${MASTER_IP} -i ${IDENTITYFILE}"
    SCP_FLAGS="-q -o ProxyJump=${USER}@${MASTER_IP} -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} -o UserKnownHostsFile=/dev/null -i ${IDENTITYFILE}"
    
    for host in $(cat $LOGFILEFOLDER/host.list)
    do
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host $host"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
        scp ${SCP_FLAGS} collectlogs.sh ${USER}@${host}:/home/${USER}/
        ssh ${SSH_FLAGS} ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
        scp ${SCP_FLAGS} ${USER}@${host}:/home/${USER}/kube_logs.tar.gz ${LOGFILEFOLDER}/kube_logs.tar.gz
        tar -xzf $LOGFILEFOLDER/kube_logs.tar.gz -C $LOGFILEFOLDER
        rm $LOGFILEFOLDER/kube_logs.tar.gz
        
        # Removing temp files from node
        ssh ${SSH_FLAGS} ${USER}@${host} "rm -f collectlogs.sh kube_logs.tar.gz"
    done
    
    rm $LOGFILEFOLDER/host.list
fi

# Aggregate ERRORS.txt
if [ `find $LOGFILEFOLDER -name ERRORS.txt | wc -w` -ne "0" ];
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Known issues found. Details: $LOGFILEFOLDER/ALL_ERRORS.txt"
    cat $LOGFILEFOLDER/*/ERRORS.txt &> $LOGFILEFOLDER/ALL_ERRORS.txt
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done collecting Kubernetes logs"

if [ "$UPLOAD_LOGS" == "true" ]; then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing logs"
    createSADirectories
    copyContainerLogsToSADirectory
    cp ${LOGFILEFOLDER}/*/daemons/kubelet-*.log ${SA_DIR}
    cp ${LOGFILEFOLDER}/*/daemons/docker-*.log ${SA_DIR}
    cp ${LOGFILEFOLDER}/*/daemons/etcd-*.log ${SA_DIR}
    
    #storage account variables
    SA_NAME="kubernetesdiagnostics"
    SA_RESOURCE_GROUP="kubernetesdiagnostics"
    
    ensureResourceGroup
    ensureStorageAccount
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"
