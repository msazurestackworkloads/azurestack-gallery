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
    #mkdir -p $SCRIPTSFOLDER
    if [ "$(ls -A $SCRIPTSFOLDER)" ]; then
        log_level -i "Scripts available skipping download"
    else
        log_level -i "Scripts not available locally downloading from $ARTIFACTSURL"
        
        for script in common detectors collectlogs collectlogsdvm hosts
        do
            if [ -f $SCRIPTSFOLDER/$script.sh ]; then
                log_level -i "Dependency '$script.sh' already in local file system"
            fi
            
            curl -fs $ARTIFACTSURL/diagnosis/$script.sh -o $SCRIPTSFOLDER/$script.sh
            
            if [ ! -f $SCRIPTSFOLDER/$script.sh ]; then
                log_level -e "Required script not available. URL: $ARTIFACTSURL/diagnosis/$script.sh"
                log_level -e "You may be running an older version. Download the latest script from github: https://aka.ms/AzsK8sLogCollectorScript"
                exit 1
            fi
        done
    fi
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

test $ALLNAMESPACES -eq 0 && unset NAMESPACES

# Print user input
echo ""
echo "user:             $USER"
echo "identity-file:    $IDENTITYFILE"
echo "master-host:      $MASTER_HOST"
echo "vmd-host:         $DVM_HOST"
echo "namespaces:       ${NAMESPACES:-all}"
echo ""

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
SCRIPTSFOLDER="./KubernetesDiagnosis/scripts"
mkdir -p $SCRIPTSFOLDER
mkdir -p $LOGFILEFOLDER
mkdir -p ~/.ssh

# Download scripts from github
ARTIFACTSURL="${ARTIFACTSURL:-https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/2.0}"
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

log_level -i "Testing SSH keys"
TEST_HOST="${MASTER_HOST:-$DVM_HOST}"
ssh -q $USER@$TEST_HOST "exit"

if [ $? -ne 0 ]; then
    log_level -e "Error connecting to the server"
    log_level -e "Aborting log collection process"
    exit 1
fi

if [ -n "$MASTER_HOST" ]
then
    log_level -i "About to collect cluster logs"
    
    log_level -i "Looking for cluster hosts"
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
        log_level -i "Processing host $host"
        
        log_level -i "Uploading scripts"
        scp -q -r $SCRIPTSFOLDER/*.sh $USER@$host:/home/$USER/
        ssh -q -t $USER@$host "sudo chmod 744 common.sh detectors.sh collectlogs.sh; ./collectlogs.sh $NAMESPACES;"
        
        log_level -i "Downloading logs"
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
    log_level -i "About to collect VMD logs"
    
    log_level -i "Uploading scripts"
    scp -q -r $SCRIPTSFOLDER/*.sh $USER@$DVM_HOST:/home/$USER/
    ssh -q -t $USER@$DVM_HOST "sudo chmod 744 common.sh detectors.sh collectlogsdvm.sh; ./collectlogsdvm.sh;"
    
    log_level -i "Downloading logs"
    scp -q $USER@$DVM_HOST:"/home/$USER/dvm_logs.tar.gz" $LOGFILEFOLDER/dvm_logs.tar.gz
    tar -xzf $LOGFILEFOLDER/dvm_logs.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/dvm_logs.tar.gz
    
    log_level -i "Removing temp files from DVM"
    ssh -q -t $USER@$DVM_HOST "rm -f common.sh detectors.sh collectlogs.sh collectlogsdvm.sh dvm_logs.tar.gz"
fi

# Aggregate ERRORS.txt
if [ `find $LOGFILEFOLDER -name ERRORS.txt | wc -w` -ne "0" ];
then
    log_level -i "Known issues found. Details: $LOGFILEFOLDER/ALL_ERRORS.txt"
    cat $LOGFILEFOLDER/*/ERRORS.txt &> $LOGFILEFOLDER/ALL_ERRORS.txt
fi

log_level -i "Done collecting Kubernetes logs"
log_level -i "Logs can be found in this location: $LOGFILEFOLDER"
