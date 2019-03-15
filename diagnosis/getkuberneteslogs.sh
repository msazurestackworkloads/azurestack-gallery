#!/bin/bash

function restore_ssh_config {
    # Restore only if previously backed up
    if [[ -v SSH_CONFIG_BAK ]]; then
        if [ -f $SSH_CONFIG_BAK ]; then 
            rm ~/.ssh/config
            mv $SSH_CONFIG_BAK ~/.ssh/config
        fi
    fi
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
    echo "  $0 -i id_rsa -m 192.168.102.34 -u azureuser"
    echo "  $0 --identity-file id_rsa --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo "  $0 --identity-file id_rsa --master-host 192.168.102.34 --user azureuser --vmd-host 192.168.102.32"
    echo "" 
    echo "Options:"
    echo "  -u, --user              User name associated to the identifity-file"
    echo "  -i, --identity-file     RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -m, --master-host       A master node's public IP or FQDN (host name starts with 'k8s-master-')"
    echo "  -d, --vmd-host          The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -h, --help              Print the command usage"
    exit 1
}


if [ "$#" -eq 0 ]
then
    printUsage
fi

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
        IDENTITYFILE="$2"
        ;;
        -m|--master-host)
        MASTER_HOST="$2"
        ;;
        -d|--vmd-host)
        DVM_HOST="$2"
        ;;
        -u|--user)
        USER="$2"
        ;;
        -h|--help)
        printUsage
        ;;
        *)
        echo ""    
        echo "[ERR] Incorrect parameter $1"    
        printUsage
        ;;
    esac

    if [ "$#" -ge 2 ]
    then
        shift 2
    else
        shift
    fi
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
    cat $IDENTITYFILE | grep -q "BEGIN RSA PRIVATE KEY" || { echo "The identity file $IDENTITYFILE is not a RSA Private Key file."; echo "A RSA private key file starts with '-----BEGIN RSA PRIVATE KEY-----''"; exit 1; }
fi

# Print user input
echo ""
echo "user: $USER"
echo "identity-file: $IDENTITYFILE"
echo "master-host: $MASTER_HOST"
echo "vmd-host: $DVM_HOST"
echo ""

NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
SCRIPTSFOLDER="$LOGFILEFOLDER/scripts"
mkdir -p $LOGFILEFOLDER/scripts

# Download scripts from github
ARTIFACTSURL="${ARTIFACTSURL:-https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master}"
download_scripts $ARTIFACTSURL

if [ -n "$MASTER_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect cluster logs"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Looking for cluster hosts"
    scp -q -i $IDENTITYFILE $SCRIPTSFOLDER/hosts.sh $USER@$MASTER_HOST:/home/$USER/hosts.sh
    ssh -tq -i $IDENTITYFILE $USER@$MASTER_HOST "sudo chmod 744 hosts.sh; ./hosts.sh $NOW"
    scp -q -i $IDENTITYFILE $USER@$MASTER_HOST:"/home/$USER/cluster-info.$NOW" $LOGFILEFOLDER/cluster-info.tar.gz
    ssh -tq -i $IDENTITYFILE $USER@$MASTER_HOST "sudo rm -f cluster-info.$NOW hosts.sh"
    tar -xzf $LOGFILEFOLDER/cluster-info.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/cluster-info.tar.gz

    # Backup .ssh/config
    SSH_CONFIG_BAK=~/.ssh/config.$NOW
    if [ ! -f ~/.ssh/config ]; then touch ~/.ssh/config; fi
    mv ~/.ssh/config $SSH_CONFIG_BAK;

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
        scp -q -i $IDENTITYFILE -r $SCRIPTSFOLDER/*.sh $USER@$host:/home/$USER/
        ssh -tq -i $IDENTITYFILE $USER@$host "sudo chmod 744 common.sh detectors.sh collectlogs.sh; ./collectlogs.sh;"
        
        echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
        scp -q -i $IDENTITYFILE $USER@$host:"/home/$USER/kube_logs.tar.gz" $LOGFILEFOLDER/kube_logs.tar.gz
        tar -xzf $LOGFILEFOLDER/kube_logs.tar.gz -C $LOGFILEFOLDER
        rm $LOGFILEFOLDER/kube_logs.tar.gz

        # Removing temp files from node
        ssh -tq -i $IDENTITYFILE $USER@$host "if [ -f common.sh ]; then rm -f common.sh; fi;"
        ssh -tq -i $IDENTITYFILE $USER@$host "if [ -f detectors.sh ]; then rm -f detectors.sh; fi;"
        ssh -tq -i $IDENTITYFILE $USER@$host "if [ -f collectlogs.sh ]; then rm -f collectlogs.sh; fi;"
        ssh -tq -i $IDENTITYFILE $USER@$host "if [ -f collectlogsdvm.sh ]; then rm -f collectlogsdvm.sh; fi;"
        ssh -tq -i $IDENTITYFILE $USER@$host "if [ -f kube_logs.tar.gz ]; then rm -f kube_logs.tar.gz; fi;"
    done

    rm $LOGFILEFOLDER/host.list
fi

if [ -n "$DVM_HOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect VMD logs"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
    scp -q -i $IDENTITYFILE -r $SCRIPTSFOLDER/*.sh $USER@$DVM_HOST:/home/$USER/
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "sudo chmod 744 common.sh detectors.sh collectlogsdvm.sh; ./collectlogsdvm.sh;"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
    scp -q -i $IDENTITYFILE $USER@$DVM_HOST:"/home/$USER/dvm_logs.tar.gz" $LOGFILEFOLDER/dvm_logs.tar.gz
    tar -xzf $LOGFILEFOLDER/dvm_logs.tar.gz -C $LOGFILEFOLDER
    rm $LOGFILEFOLDER/dvm_logs.tar.gz

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Removing temp files from DVM"
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f common.sh ]; then rm -f common.sh; fi;"
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f detectors.sh ]; then rm -f detectors.sh; fi;"
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f collectlogs.sh ]; then rm -f collectlogs.sh; fi;"
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f collectlogsdvm.sh ]; then rm -f collectlogsdvm.sh; fi;"
    ssh -tq -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f dvm_logs.tar.gz ]; then rm -f dvm_logs.tar.gz; fi;"
fi

# Aggregate ERRORS.txt
if [ `find $LOGFILEFOLDER -name ERRORS.txt | wc -w` -ne "0" ]; 
then 
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Known issues found. Details: $LOGFILEFOLDER/ALL_ERRORS.txt"
    cat $LOGFILEFOLDER/*/ERRORS.txt &> $LOGFILEFOLDER/ALL_ERRORS.txt
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done collecting Kubernetes logs"
echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"
