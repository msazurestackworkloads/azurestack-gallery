#!/bin/bash

validateKeys()
{
    host=$1
    flags=$2
    
    ssh ${flags} ${USER}@${host} "exit"
    
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to host ${host}"
        exit 1
    fi
}

validateResourceGroup()
{
    LOCATION=$(az group show -n ${RESOURCE_GROUP} --query location --output tsv)
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Specified resource group ${RESOURCE_GROUP} not found in current subscription."
        exit 1
    fi
}

checkRequirements()
{
    if ! command -v az &> /dev/null; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] azure-cli not available, please install and configure following this indications: https://docs.microsoft.com/azure-stack/user/azure-stack-version-profiles-azurecli2"
        exit 1
    fi
}

copyLogsToSADirectory()
{
    az vm list -g ${RESOURCE_GROUP} --show-details --query "[*].{host:name,akse:tags.aksEngineVersion}" --output table | grep 'k8s-' > ${SA_DIR}/akse-version.txt
    
    cp ${LOGFILEFOLDER}/k8s-*.zip ${SA_DIR}
    cp ${LOGFILEFOLDER}/vmd-*.zip ${SA_DIR}
    cp ${LOGFILEFOLDER}/cluster-snapshot.zip ${SA_DIR}
    cp ${LOGFILEFOLDER}/resources/* ${SA_DIR}
    
    if [ -n "$API_MODEL" ]
    then
        cp ${API_MODEL} ${SA_DIR}
    fi
}

deleteSADirectory()
{
    rm -rf ${LOGFILEFOLDER}/data
}

createSADirectories()
{
    local SA_DIR_DATE=$(echo $NOW | head -c 8)
    local SA_DIR_HOUR=$(echo $NOW | tail -c 7 | head -c 2)
    local SA_DIR_MIN=$(echo $NOW | tail -c 5 | head -c 2)
    SA_CONTAINER_DIR="data/d=${SA_DIR_DATE}/h=${SA_DIR_HOUR}/m=${SA_DIR_MIN}"
    SA_DIR="${LOGFILEFOLDER}/${SA_CONTAINER_DIR}"
    mkdir -p ${SA_DIR}
}

ensureResourceGroup()
{
    SA_RESOURCE_GROUP="KubernetesLogs"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Ensuring resource group: ${SA_RESOURCE_GROUP}"
    az group create -n ${SA_RESOURCE_GROUP} -l ${LOCATION} 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error ensuring resource group ${SA_RESOURCE_GROUP}"
        exit 1
    fi
}

ensureStorageAccount()
{
    SA_NAME="diagnostics"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Ensuring storage account: ${SA_NAME}"
    az storage account create --name ${SA_NAME} --resource-group ${SA_RESOURCE_GROUP} --location ${LOCATION} --sku Premium_LRS --https-only true 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error ensuring storage account ${SA_NAME}"
        exit 1
    fi
}

ensureStorageAccountContainer()
{
    SA_CONTAINER="kuberneteslogs"
    
    echo "$(date +%Y%m%d%H%M%S)][INFO] Ensuring storage account container: ${SA_CONTAINER}"
    az storage container create --name ${SA_CONTAINER} --account-name ${SA_NAME}
    if [ $? -ne 0 ]; then
        echo "$(date +%Y%m%d%H%M%S)][ERR] Error ensuring storage account container ${SA_CONTAINER}"
        exit 1
    fi
}

uploadLogs()
{
    echo "$(date +%Y%m%d%H%M%S)][INFO] Uploading log files to container: ${SA_CONTAINER}"
    az storage blob upload-batch -d ${SA_CONTAINER} -s ${SA_DIR} --destination-path ${SA_CONTAINER_DIR} --account-name ${SA_NAME}
    if [ $? -ne 0 ]; then
        echo "$(date +%Y%m%d%H%M%S)][ERR] Error uploading log files to container ${SA_CONTAINER}"
        exit 1
    fi
}

processHost()
{
    host=$1
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host ${host}"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:/home/${USER}/${host}.zip ${LOGFILEFOLDER}/${host}.zip
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "rm -f collectlogs.sh ${host}.zip"
}

processDvmHost()
{
    host=$1
    
    DVM_NAME=$(az vm list -g ${RESOURCE_GROUP} --show-details --query "[*].{Name:name,ip:privateIps}" --output tsv | grep 'vmd-' | cut -f 1 )
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing dvm-host ${host}"
    scp ${SCP_FLAGS} collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} ${USER}@${host}:/home/${USER}/${DVM_NAME}.zip ${LOGFILEFOLDER}/${DVM_NAME}.zip
    ssh ${SSH_FLAGS} ${USER}@${host} "rm -f collectlogs.sh ${DVM_NAME}.zip"
}

processWindowsHost()
{
    host=$1
    #pass=$2

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing windows-host ${host}"
    #ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo apt-get install sshpass -y"
    #WIN_PROXY_CMD="ssh ${KNOWN_HOSTS_OPTIONS} ${USER}@${MASTER_IP} -W %h:%p"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" collect-windows-logs.ps1 ${USER}@${host}:"C:/k/debug/collect-windows-logs.ps1"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; Start-Process PowerShell -Verb RunAs; C:/k/debug/collect-windows-logs.ps1"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:"C:/Users/azureuser/win_log_${host}.zip" ${LOGFILEFOLDER}/"win_log_${host}.zip"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; rm C:/k/debug/collect-windows-logs.ps1; rm C:/Users/azureuser/win_log_${host}.zip"
}

printUsage()
{
    echo "$0 collects diagnostics from Kubernetes clusters provisioned by AKS Engine"
    echo ""
    echo "Usage:"
    echo "  $0 [flags]"
    echo ""
    echo "Flags:"
    echo "  -u, --user                        The administrator username for the cluster VMs"
    echo "  -i, --identity-file               RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -g, --resource-group              Kubernetes cluster resource group"
    echo "      --api-model                   AKS Engine Kubernetes cluster definition json file"
    echo "      --upload-logs                 Persists retrieved logs in an Azure Stack storage account"
    echo "      --disable-host-key-checking   Sets SSH's StrictHostKeyChecking option to \"no\" while the script executes. Only use in a safe environment."
    echo "      --windows-nodes-password      Password of Windows Nodes if logs on Windows Nodes need to be collected"
    echo "  -h, --help                        Print script usage"
    echo ""
    echo "Examples:"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg --disable-host-key-checking"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg -n default -n monitoring"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg --upload-logs --api-model clusterDefinition.json"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg --upload-logs"
    
    exit 1
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

NAMESPACES="kube-system"
UPLOAD_LOGS="false"

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
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
        --api-model)
            API_MODEL="$2"
            shift 2
        ;;
        --upload-logs)
            UPLOAD_LOGS="true"
            shift
        ;;
        --disable-host-key-checking)
            KNOWN_HOSTS_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR'
            shift
        ;;
        -w|--windows-nodes-password)
            WINDOWS_NODES_PASSWORD="$2"
            shift 2
        ;;
        -h|--help)
            printUsage
        ;;
        *)
            echo ""
            echo "[ERR] Unexpected flag $1"
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
    echo "[ERR] identity-file $IDENTITYFILE not found"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep -q "BEGIN \(RSA\|OPENSSH\) PRIVATE KEY" \
    || { echo "Provided identity file $IDENTITYFILE is not a RSA Private Key file."; echo "A RSA private key starts with '-----BEGIN [RSA|OPENSSH] PRIVATE KEY-----''"; exit 1; }
fi

if [ -z "$RESOURCE_GROUP" ]
then
    echo ""
    echo "[ERR] --resource-group is required"
    printUsage
    exit 1
fi

if [ -n "$API_MODEL" ]
then
    if [ -n  "$(grep -e secret -e "BEGIN CERTIFICATE" -e "BEGIN RSA PRIVATE KEY" $API_MODEL)" ] || [ -n "$(grep -Po '"secret": *\K"[^"]*"' $API_MODEL | sed -e 's/^"//' -e 's/"$//')" ]
    then
        echo "[ERR] --api-model contains sensitive information (secrets or certificates); please remove it before running the tool"
        exit 1
    fi
fi

# Print user input
echo ""
echo "user:                    $USER"
echo "identity-file:           $IDENTITYFILE"
echo "resource-group:          $RESOURCE_GROUP"
echo "upload-logs:             $UPLOAD_LOGS"
echo ""

NOW=`date +%Y%m%d%H%M%S`
LOGFILEFOLDER="_output/${RESOURCE_GROUP}-${NOW}"
mkdir -p $LOGFILEFOLDER

SSH_FLAGS="-q -t -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"
SCP_FLAGS="-q -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"

checkRequirements
validateResourceGroup

# DVM
DVM_HOST=$(az network public-ip list -g ${RESOURCE_GROUP} --query "[*].{Name:name,ip:ipAddress}" --output tsv | grep 'vmd-' | head -n 1 | cut -f 2)

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with DVM host"
    validateKeys ${DVM_HOST} "${SSH_FLAGS}"
    
    processDvmHost ${DVM_HOST}
fi

# CLUSTER NODES
MASTER_IP=$(az network public-ip list -g ${RESOURCE_GROUP} --query "[*].{Name:name,ip:ipAddress}" --output tsv | grep 'k8s-master' | cut -f 2)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Error fetching the master nodes' load balancer IP"
    exit 1
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with cluster nodes"
validateKeys ${MASTER_IP} "${SSH_FLAGS}"

if [ -n "$MASTER_IP" ]
then
    scp ${SCP_FLAGS} hosts.sh ${USER}@${MASTER_IP}:/home/${USER}/hosts.sh
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo chmod 744 hosts.sh; ./hosts.sh"
    scp ${SCP_FLAGS} ${USER}@${MASTER_IP}:/home/${USER}/cluster-snapshot.zip ${LOGFILEFOLDER}/cluster-snapshot.zip
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo rm -f cluster-snapshot.zip hosts.sh"
    
    CLUSTER_NODES=$(az vm list -g ${RESOURCE_GROUP} --show-details --query "[*].{Name:name,ip:privateIps}" --output tsv | grep 'k8s-' | cut -f 1)
    PROXY_CMD="ssh -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS} ${USER}@${MASTER_IP} -W %h:%p"

    for host in ${CLUSTER_NODES}
    do
        processHost ${host}
    done

    # WINDOWS NODES
    if [ -n "$WINDOWS_NODES_PASSWORD" ]
    then
        #Get Windoews nodes
        WINDOWS_NODES=$(az vm list -g ${RESOURCE_GROUP} --show-details --query "[*].{Name:name,ip:privateIps}" --output tsv | grep -v 'k8s-\|vmd-' | cut -f 1)

        if [ -z "$WINDOWS_NODES" ]
        then
            echo "[INFO] Failed to find windows nodes, skipping windows nodes log collection..."
        else
            for winhost in ${WINDOWS_NODES}
            do
                processWindowsHost ${winhost} 
                # ${WINDOWS_NODES_PASSWORD}
            done
        fi
    fi

fi

mkdir -p $LOGFILEFOLDER/resources
az network vnet list -g ${RESOURCE_GROUP} > ${LOGFILEFOLDER}/resources/vnets.json

# UPLOAD
if [ "$UPLOAD_LOGS" == "true" ]; then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing logs"
    createSADirectories
    copyLogsToSADirectory
    ensureResourceGroup
    ensureStorageAccount
    ensureStorageAccountContainer
    uploadLogs
    deleteSADirectory
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found here: $LOGFILEFOLDER"
