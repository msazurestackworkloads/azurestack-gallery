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
    az vm list -g ${RESOURCE_GROUP} --show-details --query "[?contains(name, 'k8s-')].{host:name,akse:tags.aksEngineVersion}" --output table > ${SA_DIR}/akse-version.txt
    
    cp ${LOGFILEFOLDER}/*.zip ${SA_DIR}
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
    SA_NAME="k8slogs$(date +%Y%m%d%H%M%S)"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Ensuring storage account: ${SA_NAME}"
    az storage account show --name ${SA_NAME} --resource-group ${SA_RESOURCE_GROUP} 1> /dev/null 2> /dev/null
    if [ $? -eq 0 ]; then
        return
    fi
    az storage account create --name ${SA_NAME} --resource-group ${SA_RESOURCE_GROUP} --location ${LOCATION} --sku Premium_LRS --https-only true 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error ensuring storage account ${SA_NAME}"
        exit 1
    fi
}

ensureStorageAccountContainer()
{
    SA_CONTAINER=$(echo "${RESOURCE_GROUP}" | sed 's/[_-]//g' | sed -e 's/\(.*\)/\L\1/')
    
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
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity to host ${host}"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "exit"
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to host ${host}"
        return
    fi

    hostName=$(ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "hostname")
    hostName=$(echo ${hostName} | sed 's/[[:space:]]*$//')
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host ${hostName}"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:/home/${USER}/${hostName}.zip ${LOGFILEFOLDER}/${hostName}.zip
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "rm -f collectlogs.sh ${hostName}.zip"
}

processDvmHost()
{
    host=$1
    
    DVM_NAME=$(az vm list -g ${RESOURCE_GROUP} --show-details --query "[?contains(name, 'vmd-')].{Name:name}" --output tsv | head -n 1)
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing dvm-host ${host}"
    scp ${SCP_FLAGS} collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} ${USER}@${host}:/home/${USER}/${DVM_NAME}.zip ${LOGFILEFOLDER}/${DVM_NAME}.zip
    ssh ${SSH_FLAGS} ${USER}@${host} "rm -f collectlogs.sh ${DVM_NAME}.zip"
}

processWindowsHost()
{
    host=$1
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity to host ${host}"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "exit"
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to host ${host}"
        return
    fi

    # It has to store the hostname in a file first to avoid whitespace from Windows cmd output.
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} 'powershell; $env:COMPUTERNAME > %HOMEPATH%\hostname.txt'
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:'%HOMEPATH%/hostname.txt' hostname.txt
    hostName=$(cat hostname.txt | sed 's/[[:space:]]*$//')
    rm hostname.txt -f

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing windows-host ${hostName}"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" azs-collect-windows-logs.ps1 ${USER}@${host}:"C:/k/debug/azs-collect-windows-logs.ps1"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; Start-Process PowerShell -Verb RunAs; C:/k/debug/azs-collect-windows-logs.ps1"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:"C:/Users/${USER}/win_log_${hostName}.zip" ${LOGFILEFOLDER}/"win_log_${hostName}.zip"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; rm C:/k/debug/azs-collect-windows-logs.ps1; rm C:/Users/${USER}/win_log_${hostName}.zip"
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

NAMESPACES=""
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
        -n|--user-namespace )
            NAMESPACES="${NAMESPACES},$2"
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
DVM_HOST=$(az network public-ip list -g ${RESOURCE_GROUP} --query "[?contains(name, 'vmd-')].{ip:ipAddress}" --output tsv | head -n 1)

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with DVM host"
    validateKeys ${DVM_HOST} "${SSH_FLAGS}"
    
    processDvmHost ${DVM_HOST}
fi

# CLUSTER NODES
MASTER_IP=$(az network public-ip list -g ${RESOURCE_GROUP} --query "[?contains(name, 'k8s-master') || contains(name, 'aks-master')].{ip:ipAddress}" --output tsv)
if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Error fetching the master nodes' load balancer IP"
    exit 1
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with cluster nodes"
validateKeys ${MASTER_IP} "${SSH_FLAGS}"

if [ -n "$MASTER_IP" ]
then
    scp ${SCP_FLAGS} hosts.sh ${USER}@${MASTER_IP}:/home/${USER}/hosts.sh
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo chmod 744 hosts.sh; ./hosts.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} ${USER}@${MASTER_IP}:/home/${USER}/cluster-snapshot.zip ${LOGFILEFOLDER}/cluster-snapshot.zip
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo rm -f cluster-snapshot.zip hosts.sh"
    
    LINUX_NODES=$(az vm list -g ${RESOURCE_GROUP} --query "[?storageProfile.osDisk.osType=='Linux' && tags != null && contains(tags.orchestrator, 'Kubernetes')].{Name:name}" --output tsv | sed 's/[[:blank:]]*$//')
    PROXY_CMD="ssh -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS} ${USER}@${MASTER_IP} -W %h:%p"

    for host in ${LINUX_NODES}
    do
        processHost ${host}
    done

    #Get Windoews nodes log if Windows nodes exist
    WINDOWS_NODES=$(az vm list -g ${RESOURCE_GROUP} --query "[?storageProfile.osDisk.osType=='Windows' && tags != null && contains(tags.orchestrator, 'Kubernetes')].{Name:name}" --output tsv | sed 's/[[:blank:]]*$//')

    if [ -n "$WINDOWS_NODES" ]
    then
        for winhost in ${WINDOWS_NODES}
        do
            processWindowsHost ${winhost} 
        done
    fi

    # Search VMSS nodes
    VMSS_LIST=$(az vmss list -g ${RESOURCE_GROUP} --query "[?tags != null && contains(tags.orchestrator, 'Kubernetes')].{name:name, osType:virtualMachineProfile.storageProfile.osDisk.osType}")
    for VMSS in $(echo "${VMSS_LIST}" | jq -c '.[]'); do
        VMSS_NAME=$(echo ${VMSS} | jq -r '.name')
        OS_TYPE=$(echo ${VMSS} | jq -r '.osType')
        VMSS_NODES=$(az network nic list -g ${RESOURCE_GROUP} --query "[?name=='${VMSS_NAME}'].{ip:ipConfigurations[0].privateIpAddress}" --output tsv | sed 's/[[:blank:]]*$//')
        
        if [ "$OS_TYPE" == "Linux" ]
        then
            for host in ${VMSS_NODES}
            do
                processHost ${host}
            done
        else
            for host in ${VMSS_NODES}
            do
                processWindowsHost ${host} 
            done
        fi
    done

fi

mkdir -p $LOGFILEFOLDER/resources
az network vnet list -g ${RESOURCE_GROUP} > ${LOGFILEFOLDER}/resources/vnets.json

# UPLOAD
if [ "$UPLOAD_LOGS" == "true" ]; then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading logs to storage account..."
    createSADirectories
    copyLogsToSADirectory
    ensureResourceGroup
    ensureStorageAccount
    ensureStorageAccountContainer
    uploadLogs
    deleteSADirectory
    echo "[$(date +%Y%m%d%H%M%S)][INFO] The logs are uploaded to resource group: ${SA_RESOURCE_GROUP}, stroage account: ${SA_NAME}, container: ${SA_CONTAINER}."
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found here: $LOGFILEFOLDER"
