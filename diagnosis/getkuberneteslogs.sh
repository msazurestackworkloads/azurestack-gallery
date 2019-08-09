#!/bin/bash

restore_ssh_config()
{
    # Restore only if previously backed up
    if [[ -v SSH_CONFIG_BAK ]]; then
        if [ -f $SSH_CONFIG_BAK ]; then
            rm ~/.ssh/config
            mv $SSH_CONFIG_BAK ~/.ssh/config
        fi
    fi
    
    # Restore only if previously backed up
    if [[ -v SSH_KEY_BAK ]]; then
        if [ -f $SSH_KEY_BAK ]; then
            rm ~/.ssh/id_rsa
            mv $SSH_KEY_BAK ~/.ssh/id_rsa
            # Remove if empty
            if [ -a ~/.ssh/id_rsa -a ! -s ~/.ssh/id_rsa ]; then
                rm ~/.ssh/id_rsa
            fi
        fi
    fi
}

requirements()
{
    found=0

    azureversion=$(az --version)
    if [ $? -eq 0 ]; then
        found=$((found + 1))
        echo "Found azure-cli version: $azureversion"
    else
        echo "azure-cli is missing. Please install azure-cli from"
        echo "https://docs.microsoft.com/en-us/azure-stack/user/azure-stack-version-profiles-azurecli2"
    fi
}

# Restorey SSH config file always, even if the script ends with an error
trap restore_ssh_config EXIT

printUsage()
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -m 192.168.102.34 -u azureuser -n default -n monitoring --disable-host-key-checking"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32 --spn-client-id 00000000-aaaa-aaaa-0000-aaaaaaaaaaaa --spn-client-secret 00000000-aaaa-aaaa-0000-aaaaaaaaaaaa --tenant-id 00000000-0000-0000-0000-000000000000 --upload-logs"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -m, --master-host               A master node's public IP or FQDN (host name starts with 'k8s-master-')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  --spn-client-id                 Service Principal client Id used to create the Kubernetes cluster"
    echo "  --spn-client-secret             Service Principal client secret used to create the Kubernetes cluster"
    echo "  -t, --tenant-id                 Tenant Id"
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
# Revert once CI passes the new flag => STRICT_HOST_KEY_CHECKING="ask"
STRICT_HOST_KEY_CHECKING="no"
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
        --spn-client-id)
            SPN_CLIENT_ID="$2"
            shift 2
        ;;
        --spn-client-secret)
            SPN_CLIENT_SECRET="$2"
            shift 2
        ;;
        -t|--tenant-id)
            TENANT_ID="$2"
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

if [ -z "$SPN_CLIENT_ID" -a -z "$SPN_CLIENT_SECRET" ] && [ -n "$UPLOAD_LOGS" ]
then
    echo ""
    echo "[ERR] Service Principal details should be provided if logs are stored in a storage account"
    printUsage
    exit 1
fi

if [ -z "$TENANT_ID" ] && [ -n "$UPLOAD_LOGS" ]
then
    echo ""
    echo "[ERR] Tenant Id should be provided if logs are stored in a storage account"
    printUsage
fi

if [ -z "$LOCATION" ] && [ -n "$UPLOAD_LOGS" ]
then
    echo ""
    echo "[ERR] Location should be provided if logs are stored in a storage account"
    printUsage
fi

test $ALLNAMESPACES -eq 0 && unset NAMESPACES

# Print user input
echo ""
echo "user:                    $USER"
echo "identity-file:           $IDENTITYFILE"
echo "master-host:             $MASTER_HOST"
echo "vmd-host:                $DVM_HOST"
echo "spn-client-id:           $SPN_CLIENT_ID"
echo "spn-client-secret:       $SPN_CLIENT_SECRET"
echo "tenant-id:               $TENANT_ID"
echo "upload-logs:             $UPLOAD_LOGS"
echo "namespaces:              ${NAMESPACES:-all}"
echo ""

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
mkdir -p $LOGFILEFOLDER
mkdir -p ~/.ssh

# Backup .ssh/config
SSH_CONFIG_BAK=~/.ssh/config.$NOW
if [ ! -f ~/.ssh/config ]; then touch ~/.ssh/config; fi
mv ~/.ssh/config $SSH_CONFIG_BAK;

# Backup .ssh/id_rsa
SSH_KEY_BAK=~/.ssh/id_rsa.$NOW
if [ ! -f ~/.ssh/id_rsa ]; then touch ~/.ssh/id_rsa; fi
mv ~/.ssh/id_rsa $SSH_KEY_BAK;
cp $IDENTITYFILE ~/.ssh/id_rsa

echo "Host *" >> ~/.ssh/config
echo "    StrictHostKeyChecking $STRICT_HOST_KEY_CHECKING" >> ~/.ssh/config
echo "    UserKnownHostsFile /dev/null" >> ~/.ssh/config
echo "    LogLevel ERROR" >> ~/.ssh/config

echo "[$(date +%Y%m%d%H%M%S)][INFO] Testing SSH keys"
TEST_HOST="${MASTER_HOST:-$DVM_HOST}"
ssh -q $USER@$TEST_HOST "exit"

if [ $? -ne 0 ]; then
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to the server"
    echo "[$(date +%Y%m%d%H%M%S)][ERR] Aborting log collection process"
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
    
    # Configure SSH bastion host. Technically only needed for worker nodes.
    for host in $(cat $LOGFILEFOLDER/host.list)
    do
        # https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Proxies_and_Jump_Hosts#Passing_Through_One_or_More_Gateways_Using_ProxyJump
        echo "Host $host" >> ~/.ssh/config
        echo "    ProxyJump $USER@$MASTER_HOST" >> ~/.ssh/config
    done
    
    for host in $(cat $LOGFILEFOLDER/host.list)
    do
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing host $host"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
        scp -q -r common.sh $USER@$host:/home/$USER/
        scp -q -r detectors.sh $USER@$host:/home/$USER/
        scp -q -r collectlogs.sh $USER@$host:/home/$USER/
        ssh -q -t $USER@$host "sudo chmod 744 common.sh detectors.sh collectlogs.sh; ./collectlogs.sh $NAMESPACES;"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
        scp -q $USER@$host:"/home/$USER/kube_logs.tar.gz" $LOGFILEFOLDER/kube_logs.tar.gz
        tar -xzf $LOGFILEFOLDER/kube_logs.tar.gz -C $LOGFILEFOLDER
        rm $LOGFILEFOLDER/kube_logs.tar.gz
        
        # Removing temp files from node
        ssh -q -t $USER@$host "rm -f common.sh detectors.sh collectlogs.sh collectlogsdvm.sh kube_logs.tar.gz"
    done
    
    rm $LOGFILEFOLDER/host.list
fi

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect VMD logs"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
    scp -q -r common.sh $USER@$DVM_HOST:/home/$USER/
    scp -q -r detectors.sh $USER@$DVM_HOST:/home/$USER/
    scp -q -r collectlogsdvm.sh $USER@$DVM_HOST:/home/$USER/
    ssh -q -t $USER@$DVM_HOST "sudo chmod 744 common.sh detectors.sh collectlogsdvm.sh; ./collectlogsdvm.sh;"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
    scp -q $USER@$DVM_HOST:"/home/$USER/dvm_logs.tar.gz" $LOGFILEFOLDER/dvm_logs.tar.gz
    tar -xzf $LOGFILEFOLDER/dvm_logs.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/dvm_logs.tar.gz
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Removing temp files from DVM"
    ssh -q -t $USER@$DVM_HOST "rm -f common.sh detectors.sh collectlogs.sh collectlogsdvm.sh dvm_logs.tar.gz"
fi

# Aggregate ERRORS.txt
if [ `find $LOGFILEFOLDER -name ERRORS.txt | wc -w` -ne "0" ];
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Known issues found. Details: $LOGFILEFOLDER/ALL_ERRORS.txt"
    cat $LOGFILEFOLDER/*/ERRORS.txt &> $LOGFILEFOLDER/ALL_ERRORS.txt
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done collecting Kubernetes logs"
echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"

if [ -n "$UPLOAD_LOGS" ]; then
    #checks if azure-cli is installed   
    requirements
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Logging into AzureStack using Azure CLI"
    #login into azurestack using spn id and secret
    az login --service-principal -u $spn_id -p $spn_secret --tenant $tenant_id
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error logging into AzureStack"
    fi
fi
