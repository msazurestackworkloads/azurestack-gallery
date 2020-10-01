#!/bin/bash -x

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

processHost()
{
    host=$1
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host ${host}"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:/home/${USER}/${host}.zip ${LOGFILEFOLDER}/${host}.zip
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "rm -f collectlogs.sh ${host}.zip"
}

processWindowsHost()
{
    host=$1

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing windows-host ${host}"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" azs-collect-windows-logs.ps1 ${USER}@${host}:"C:/k/debug/azs-collect-windows-logs.ps1"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; Start-Process PowerShell -Verb RunAs; C:/k/debug/azs-collect-windows-logs.ps1"
    scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host}:"C:/Users/${USER}/win_log_${host}.zip" ${LOGFILEFOLDER}/"win_log_${host}.zip"
    ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${host} "powershell; rm C:/k/debug/azs-collect-windows-logs.ps1; rm C:/Users/${USER}/win_log_${host}.zip"
}

processDvmHost()
{
    host=$1
    dvm_name=$2
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing dvm-host ${host}"
    scp ${SCP_FLAGS} collectlogs.sh ${USER}@${host}:/home/${USER}/collectlogs.sh
    ssh ${SSH_FLAGS} ${USER}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh ${NAMESPACES};"
    scp ${SCP_FLAGS} ${USER}@${host}:/home/${USER}/${dvm_name}.zip ${LOGFILEFOLDER}/${dvm_name}.zip
    ssh ${SSH_FLAGS} ${USER}@${host} "rm -f collectlogs.sh ${dvm_name}.zip"
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
    echo "  -n, --user-namespace              Collect logs from containers in the specified namespaces (kube-system logs are always collected)"
    echo "      --api-model                   AKS Engine Kubernetes cluster definition json file"
    echo "      --all-namespaces              Collect logs from containers in all namespaces. It overrides --user-namespace"
    echo "      --disable-host-key-checking   Sets SSH's StrictHostKeyChecking option to \"no\" while the script executes. Only use in a safe environment."
    echo "  -h, --help                        Print script usage"
    echo ""
    echo "Examples:"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg --disable-host-key-checking"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -g k8s-rg -n default -n monitoring"
    
    exit 1
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

NAMESPACES="kube-system"
ALLNAMESPACES=1

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
        --dvm-ip)
            DVM_HOST="$2"
            shift 2
        ;;
        --dvm-name)
            DVM_NAME="$2"
            shift 2
        ;;
        --master-ip)
            MASTER_IP="$2"
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

test $ALLNAMESPACES -eq 0 && unset NAMESPACES

# Print user input
echo ""
echo "user:                    $USER"
echo "identity-file:           $IDENTITYFILE"
echo "resource-group:          $RESOURCE_GROUP"
echo "namespaces:              ${NAMESPACES:-all}"
echo ""

NOW=`date +%Y%m%d%H%M%S`
LOGFILEFOLDER="_output/${RESOURCE_GROUP}-${NOW}"
mkdir -p $LOGFILEFOLDER

SSH_FLAGS="-q -t -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"
SCP_FLAGS="-q -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"


if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with DVM host"
    validateKeys ${DVM_HOST} "${SSH_FLAGS}"
    processDvmHost ${DVM_HOST} ${DVM_NAME}
fi

if [ -n "$MASTER_IP" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with master node"
    validateKeys ${MASTER_IP} "${SSH_FLAGS}"
    
    scp ${SCP_FLAGS} hosts.sh ${USER}@${MASTER_IP}:/home/${USER}/hosts.sh
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo chmod 744 hosts.sh; ./hosts.sh"
    scp ${SCP_FLAGS} ${USER}@${MASTER_IP}:/home/${USER}/cluster-snapshot.zip ${LOGFILEFOLDER}/cluster-snapshot.zip
    scp ${SCP_FLAGS} ${USER}@${MASTER_IP}:/home/${USER}/*_nodes.txt ${LOGFILEFOLDER}/.
    ssh ${SSH_FLAGS} ${USER}@${MASTER_IP} "sudo rm -f cluster-snapshot.zip hosts.sh *_nodes.txt"
    
    if [ ! -f ${LOGFILEFOLDER}/linux_nodes.txt ]
    then
        echo "Linux nodes not present"
    else
        PROXY_CMD="ssh -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS} ${USER}@${MASTER_IP} -W %h:%p"
        
        INPUT_FILE=${LOGFILEFOLDER}/linux_nodes.txt
        LINUX_NODES=$(<$INPUT_FILE)
        
        for host in ${LINUX_NODES}
        do
            processHost ${host}
        done
    fi

    if [ ! -f ${LOGFILEFOLDER}/windows_nodes.txt ]
    then
        echo "Windows nodes not present"
    else
        PROXY_CMD="ssh -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS} ${USER}@${MASTER_IP} -W %h:%p"
        
        INPUT_FILE=${LOGFILEFOLDER}/windows_nodes.txt
        WINDOWS_NODES=$(<$INPUT_FILE)
        
        for host in ${WINDOWS_NODES}
        do
            processHost ${host}
        done
    fi
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done with k8s log collection"

