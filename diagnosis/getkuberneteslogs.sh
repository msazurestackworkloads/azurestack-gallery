#!/bin/bash

function restore_ssh_config
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

retrycmd_if_failure() 
{ 
    retries=$1; 
    wait=$2; 
    for i in $(seq 1 $retries); do 
        ${@:3}; [ $? -eq 0  ] && break || sleep $wait; 
    done; 
    log_level -i "Command Executed $i times."; 
}


function login_azs()
{
    local spn_id=$1
    local spn_secret=$2
    local tenant_id=$3
    
    az login --service-principal -u $spn_id -p $spn_secret --tenant $tenant_id
}

askSubscription() {
    az account list -otable
    echo ""
    echo "Please enter the Id of the account you wish to use. If you do not see"
    echo "a valid account in the list press Ctrl+C to abort and create one."
    echo "If you leave this blank we will use the Current account."
    echo -n "> "
    read azure_subscription_id

    if [ "$azure_subscription_id" != "" ]; then
        az account set --subscription $azure_subscription_id
    else
        azure_subscription_id=$(az account list --output json | jq -r '.[] | select(.isDefault==true) | .id')
    fi
    echo "Using subscription_id: $azure_subscription_id"
}

askName() {
    echo ""
    echo "Choose a name for your resource group, storage account and client"
    echo "client. This is arbitrary, but it must not already be in use by"
    echo "any of those resources. ALPHANUMERIC ONLY. Ex: mypackerbuild"
    echo -n "> "
    read meta_name
}

createResourceGroup() {
    local location=$1
    echo "==> Creating resource group"
    az group create -n $meta_name -l $location
    if [ $? -eq 0 ]; then
        azure_group_name=$meta_name
    else
        echo "Error creating resource group: $meta_name"
        return 1
    fi
}

createStorageAccount() {

    local location=$1 

    echo "==> Creating storage account"
    az storage account create --name $meta_name --resource-group $meta_name --location $location --kind Storage --sku Standard_LRS
    if [ $? -eq 0 ]; then
        azure_storage_name=$meta_name
    else
        echo "Error creating storage account: $meta_name"
        return 1
    fi
}


retryable() {
    n=0
    until [ $n -ge $1 ]
    do
        $2 && return 0
        echo "$2 failed. Retrying..."
        n=$[$n+1]
        doSleep
    done
    echo "$2 failed after $1 tries. Exiting."
    exit 1
}


function upload_logs()
{   
    local file_to_upload=$1    
    local storage_acct=$2
    local storage_key=$3

    storage_key=$(az storage account keys list -g $metaname -n $metaname | jq '.[0].value ')

    CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
    container_name="AzureStack_KubernetesLogs_$CURRENTDATE"
    blob_name="KubernetesLogs_$CURRENTDATE"
    
    az storage container create --name $container_name --account-name $meta_name --account-key $storage_key
    az storage blob upload --container-name $container_name --file $file_to_upload --name $blob_name --account-name $meta_name --account-key $storage_key 
}
# Restorey SSH config file always, even if the script ends with an error
trap restore_ssh_config EXIT

function download_scripts
{
    ARTIFACTSURL=$1
    mkdir -p $SCRIPTSFOLDER
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Pulling dependencies from this repo: $ARTIFACTSURL"
    
    for script in common detectors collectlogs collectlogsdvm hosts
    do
        if [ -f $SCRIPTSFOLDER/$script.sh ]; then
            echo "[$(date +%Y%m%d%H%M%S)][INFO] Dependency '$script.sh' already in local file system"
        fi
        
        curl -fs $ARTIFACTSURL/diagnosis/$script.sh -o $SCRIPTSFOLDER/$script.sh
        
        if [ ! -f $SCRIPTSFOLDER/$script.sh ]; then
            echo "[$(date +%Y%m%d%H%M%S)][ERROR] Required script not available. URL: $ARTIFACTSURL/diagnosis/$script.sh"
            echo "[$(date +%Y%m%d%H%M%S)][ERROR] You may be running an older version. Download the latest script from github: https://aka.ms/AzsK8sLogCollectorScript"
            exit 1
        fi
    done
}

function printUsage
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -m 192.168.102.34 -u azureuser -n default -n monitoring --disable-host-key-checking"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -m, --master-host               A master node's public IP or FQDN (host name starts with 'k8s-master-')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -n, --user-namespace            Collect logs for containers in the passed namespace (kube-system logs are always collected)"
    echo "  --all-namespaces                Collect logs for all containers. Overrides the user-namespace flag"
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
        -l|--location)
            LOCATION="$2"
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

if [ -z "$SPN_CLIENT_ID" -a -z "$SPN_CLIENT_SECRET" ]
then
    echo ""
    echo "[ERR] Either SPN details or apimodel should be provided"
    printUsage
    exit 1
fi

if [ -z "$TENANT_ID" ]
then
    echo ""
    echo "[ERR] --tenant-id is required"
    printUsage
fi

if [ -z "$LOCATION" ]
then
    echo ""
    echo "[ERR] --tenant-id is required"
    printUsage
fi

test $ALLNAMESPACES -eq 0 && unset NAMESPACES

# Print user input
echo ""
echo "user:              $USER"
echo "identity-file:     $IDENTITYFILE"
echo "master-host:       $MASTER_HOST"
echo "vmd-host:          $DVM_HOST"
echo "namespaces:        ${NAMESPACES:-all}"
echo "spn-client-id:     $SPN_CLIENT_ID"
echo "spn-client-secret: $SPN_CLIENT_SECRET"
echo "tenant-id:         $TENANT_ID"
echo "env-name:          $ENV_NAME"
echo ""

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
SCRIPTSFOLDER="$LOGFILEFOLDER/scripts"
mkdir -p $LOGFILEFOLDER/scripts
mkdir -p ~/.ssh

# Download scripts from github
ARTIFACTSURL="${ARTIFACTSURL:-https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master}"
download_scripts $ARTIFACTSURL

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

#login into azurestack using spn id and secret
login_azs $SPN_CLIENT_ID \
    $SPN_CLIENT_SECRET \
    $TENANT_ID

askSubscription
askName
createResourceGroup $LOCATION
createStorageAccount $LOCATION

if [ -n "$MASTER_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect cluster logs"
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Looking for cluster hosts"
    scp -q $SCRIPTSFOLDER/hosts.sh $USER@$MASTER_HOST:/home/$USER/hosts.sh
    ssh -tq $USER@$MASTER_HOST "sudo chmod 744 hosts.sh; ./hosts.sh $NOW"
    scp -q $USER@$MASTER_HOST:"/home/$USER/cluster-info.$NOW" $LOGFILEFOLDER/cluster-info.tar.gz
    ssh -tq $USER@$MASTER_HOST "sudo rm -f cluster-info.$NOW hosts.sh"
    tar -xzf $LOGFILEFOLDER/cluster-info.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/cluster-info.tar.gz
    
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
        scp -q -r $SCRIPTSFOLDER/*.sh $USER@$host:/home/$USER/
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
    scp -q -r $SCRIPTSFOLDER/*.sh $USER@$DVM_HOST:/home/$USER/
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
echo "[$(date +%Y%m%d%H%M%S)][INFO] Log in to AzureStack using Azure Cli"
echo "[$(date +%Y%m%d%H%M%S)][INFO] Upload the logs to storage Account $STORAGE_ACCT"

upload_logs $LOGFILEFOLDER \
        $STORAGE_ACCT \
        $STORAGE_KEY

echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"
