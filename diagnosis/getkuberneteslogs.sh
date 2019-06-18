#!/bin/bash

RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
YELLOW='\033[0;33m'  # For crucial check success
NC='\033[0m'        # No color, back to normal


log_level()
{
    case "$1" in
        -e) echo -e "${RED}$(date) [Err]  " ${@:2}
        ;;
        -w) echo -e "${YELLOW}$(date) [Warn] " ${@:2}
        ;;
        -i) echo -e "${GREEN}$(date) [Info] " ${@:2}
        ;;
        *)  echo -e "${NC}$(date) [Debug] " ${@:2}
        ;;
    esac
}

function valid_ip()
{
    local  ip=$1
    local  stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
        && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

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

# Restorey SSH config file always, even if the script ends with an error
trap restore_ssh_config EXIT

function download_scripts
{
    ARTIFACTSURL=$1
    
    for script in common clusterlogs clusterSanityCheck detecterrors dvmlogs hosts
    do
        curl -fs $ARTIFACTSURL/diagnosis/$script.sh -o $SCRIPTSFOLDER/$script.sh
        
        if [ ! -f $SCRIPTSFOLDER/$script.sh ]; then
            log_level -e "Required script not available. URL: $ARTIFACTSURL/diagnosis/$script.sh"
            log_level -e "You may be running an older version. Download the latest script from github: https://aka.ms/AzsK8sLogCollectorScript"
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
            log_level -e "[ERR] Incorrect option $1"
            printUsage
        ;;
    esac
done

# Validate input
if [ -z "$USER" ]
then
    echo ""
    log_level -e "--user is required"
    printUsage
fi

if [ -z "$IDENTITYFILE" ]
then
    echo ""
    log_level -e "--identity-file is required"
    printUsage
fi

if [ -z "$DVM_HOST" -a -z "$MASTER_HOST" ]
then
    echo ""
    log_level -e "Either --vmd-host or --master-host should be provided"
    printUsage
fi

if [ ! -f $IDENTITYFILE ]
then
    echo ""
    log_level -e "identity-file not found at $IDENTITYFILE"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep -q "BEGIN \(RSA\|OPENSSH\) PRIVATE KEY" \
    || { log_level -e "The identity file $IDENTITYFILE is not a RSA Private Key file."; log_level -e "A RSA private key file starts with '-----BEGIN [RSA|OPENSSH] PRIVATE KEY-----''"; exit 1; }
fi

#test $ALLNAMESPACES -eq 0 && unset NAMESPACES

if [[ $ALLNAMESPACES -eq 0 ]];then
    unset NAMESPACES
    NAMESPACES="all"
fi 

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
SCRIPTSFOLDER="./DiagnosisScripts"
mkdir -p $SCRIPTSFOLDER
mkdir -p $LOGFILEFOLDER
mkdir -p ~/.ssh

ARTIFACTSURL="${ARTIFACTSURL:-https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/2.0}"

#Loading defaults
if [ -f ./defaults.env ]; then
    log_level -i "Using default settings"
    source ./defaults.env
else
    log_level -i "Downloading Defaults"
    curl -fs $ARTIFACTSURL/diagnosis/defaults.env -o ./defaults.env
    source ./defaults.env
fi

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "USER: $USER"
log_level -i "IDENTITYFILE: $IDENTITYFILE"
log_level -i "MASTER_HOST: $MASTER_HOST"
log_level -i "DVM_HOST: $DVM_HOST"
log_level -i "NAMESPACES: ${NAMESPACES:-all}"
log_level -i "RUN_SANITY_CHECKS: $RUN_SANITY_CHECKS"
log_level -i "RUN_COLLECT_CLUSTER_LOG: $RUN_COLLECT_CLUSTER_LOG"
log_level -i "FORCE_DOWNLOAD: $FORCE_DOWNLOAD"
log_level -i "-----------------------------------------------------------------------------"

# Download scripts from github
if [[ $FORCE_DOWNLOAD == "yes" ]]; then
    log_level -i "Downloading scripts and overwriting"
    download_scripts $ARTIFACTSURL
else
    if [[ -z "$(ls -A $SCRIPTSFOLDER)" ]]; then
        log_level -i "Scripts not available locally downloading"
        download_scripts $ARTIFACTSURL
    else
        log_level -i "Scripts available locally... skipping"
    fi
fi
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

log_level -i "Testing SSH keys"
TEST_HOST="${MASTER_HOST:-$DVM_HOST}"
ssh -q $USER@$TEST_HOST "exit"

if [ $? -ne 0 ]; then
    log_level -e "Error connecting to the server"
    log_level -e "Aborting log collection process"
    exit 1
fi

# Getting host ips
log_level -i "Getting Hosts"
scp -q $SCRIPTSFOLDER/hosts.sh $USER@$MASTER_HOST:/home/$USER/hosts.sh
HOSTS=$(ssh -t -q $USER@$MASTER_HOST "sudo chmod 744 hosts.sh; ./hosts.sh")

log_level -i "Validating Host addresses"
for IP in $HOSTS
do
    if valid_ip $IP ; then
        log_level -i "Host [$IP] is valid"
    else
        log_level -e "Host [$IP] is not valid"
        exit 1
    fi
done


# Configure SSH bastion host. Technically only needed for worker nodes.
for host in $HOSTS
do
    # https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Proxies_and_Jump_Hosts#Passing_Through_One_or_More_Gateways_Using_ProxyJump
    echo "Host $host" >> ~/.ssh/config
    echo "    ProxyJump $USER@$MASTER_HOST" >> ~/.ssh/config
done

#Collecting host information
log_level -i "--------------------------------------------------------------------------------------------------------------"
if [[ $RUN_SANITY_CHECKS == "yes" ]]; then
    log_level -i "Running Cluster sanity Checks"
    source $SCRIPTSFOLDER/clustersanitycheck.sh -u $USER -h "$HOSTS" -o $LOGFILEFOLDER -s $SCRIPTSFOLDER
else
    log_level -i "Skipping cluster sanity Checks"
fi
log_level -i "--------------------------------------------------------------------------------------------------------------"


if [[ $RUN_COLLECT_CLUSTER_LOGS == "yes" ]]; then
    log_level -i "Running cluster log collection"
    source $SCRIPTSFOLDER/clusterlogs.sh -u $USER -h "$HOSTS" -o $LOGFILEFOLDER -n "$NAMESPACES" -s $SCRIPTSFOLDER
else
    log_level -i "Skipping cluster log collection"
fi

log_level -i "--------------------------------------------------------------------------------------------------------------"

if [[ ! -z $DVM_HOST && $RUN_COLLECT_DVM_LOGS == "yes" ]]; then
    log_level -i "Running dvm log collection"
    source $SCRIPTSFOLDER/dvmlogs.sh -u $USER -o $LOGFILEFOLDER -d $DVM_HOST -s $SCRIPTSFOLDER
else
    log_level -i "Skipping dvm log collection"
fi

log_level -i "--------------------------------------------------------------------------------------------------------------"

if [[ $RUN_DETECT_ERRORS == "yes" ]]; then
    log_level -i "Running error detection"
    source $SCRIPTSFOLDER/detecterrors.sh -o $LOGFILEFOLDER -s $SCRIPTSFOLDER
else
    log_level -i "Skipping error detection"
fi
log_level -i "--------------------------------------------------------------------------------------------------------------"

log_level -i "Done collecting Kubernetes logs"
log_level -i "Logs can be found in this location: $LOGFILEFOLDER"
