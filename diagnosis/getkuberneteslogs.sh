#! /bin/bash

function printUsage
{
    echo ""
    echo "Usage:"    
    echo "  $FILENAME -i id_rsa -h 192.168.102.34 -u azureuser"    
    echo "  $FILENAME --identity-file id_rsa --user azureuser --vmdhost 192.168.102.32"   
    echo "  $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser --vmdhost 192.168.102.32"
    echo "  $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser --vmdhost 192.168.102.32 --force"
    echo "" 
    echo "Options:"
    echo "  -u, --user              User name associated to the identifity-file"    
    echo "  -i, --identity-file     RSA Private Key used to create the Kubernetes cluster (usually named 'id_rsa.pub')"
    echo "  -m, --master-host       The master node public IP or FQDN (host name starts with 'k8s-master-')"    
    echo "  -d, --vmd-host          The DVM public IP or FQDN (host name starts with 'vmd-')"
    echo "  -f, --force             Do not prompt before uploading private key"
    echo "  -h, --help              Print the command usage"
    exit 1
}

FILENAME=$0

if [ "$#" -eq 0 ]
then
    printUsage
fi

# Handle the named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
        IDENTITYFILE="$2"
        ;;
        -m|--master-host)
        HOST="$2"
        ;;
        -d|--vmd-host)
        DVMHOST="$2"
        ;;
        -u|--user)
        AZUREUSER="$2"
        ;;
        -f|--force)
        FORCE="Y"
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

if [ -z "$AZUREUSER" ]
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

if [ -z "$DVMHOST" -a -z "$HOST" ]
then
    echo ""
    echo "[ERR] Either --vmd-host or --master-host should be provided"
    printUsage
fi

if [ -z "$FORCE" ]
then
    FORCE="N"
else
    echo ""
    echo "[INFO] The private key will be uploaded to the Kubernetes master to collect logs"
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

echo ""
echo "user: $AZUREUSER"
echo "identity-file: $IDENTITYFILE"
echo "master-host: $HOST"
echo "vmd-host: $DVMHOST"
echo ""

CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="./KubernetesLogs_$CURRENTDATE"
ARTIFACTSURL="https://raw.githubusercontent.com/jadarsie/azurestack-gallery/log-collector"

mkdir -p $LOGFILEFOLDER

if [ -n "$HOST" ]
then
    if [ "$FORCE" = "N" ]
    then
        read -p "The private key has to be uploaded to the Kubernetes master VM $HOST to collect logs, accept (y/n)? " choice
        case "$choice" in 
        y|Y|yes|YES ) echo "Continue";;
        n|N|no|NO) echo "Aborting"; exit 0 ;;
        * ) echo "Invalid option '$choice'. Stopping the log collection process"; exit 0;;
        esac
    fi

    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect cluster logs"

    # Backup id_rsa
    IDENTITYFILEBACKUP="~/.ssh/bak/id_rsa"
    ssh -q -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f .ssh/id_rsa ]; then mkdir -p $IDENTITYFILEBACKUP; cp .ssh/id_rsa $IDENTITYFILEBACKUP; fi;"

    # Copy id_rsa into Kubernete Host VM
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading private key"
    scp -q -i $IDENTITYFILE ~/.ssh/id_rsa $AZUREUSER@$HOST:/home/$AZUREUSER/.ssh/id_rsa
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f .ssh/id_rsa ]; then sudo chmod 400 .ssh/id_rsa; fi;"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
    # scp -q -i $IDENTITYFILE common.sh $AZUREUSER@$HOST:/home/$AZUREUSER/common.sh
    # ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "sudo chmod 744 common.sh;"
    # scp -q -i $IDENTITYFILE collectlogs.sh $AZUREUSER@$HOST:/home/$AZUREUSER/collectlogs.sh
    # ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "sudo chmod 744 collectlogs.sh;"
    # scp -q -i $IDENTITYFILE collectlogsmanager.sh $AZUREUSER@$HOST:/home/$AZUREUSER/collectlogsmanager.sh
    # ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "sudo chmod 744 collectlogsmanager.sh; ./collectlogsmanager.sh;"  
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O $ARTIFACTSURL//diagnosis/collectlogsmanager.sh"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "sudo chmod 744 collectlogsmanager.sh; ./collectlogsmanager.sh"
    
    # Copy logs back to local machine
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
    scp -q -i $IDENTITYFILE $AZUREUSER@$HOST:"/home/$AZUREUSER/cluster_logs.tar.gz" $LOGFILEFOLDER/cluster_logs.tar.gz   

    # Restore id_rsa
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f $IDENTITYFILEBACKUP ] ; then mv -f $IDENTITYFILEBACKUP .ssh/id_rsa; else rm -f .ssh/id_rsa; fi;"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f $IDENTITYFILEBACKUP ]; then sudo rm -f $IDENTITYFILEBACKUP; fi;"

    # Delete scripts
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Removing temp files from cluster"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f common.sh ]; then sudo rm -f common.sh; fi;"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f collectlogs.sh ]; then sudo rm -f collectlogs.sh; fi;"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f collectlogsmanager.sh ]; then sudo rm -f collectlogsmanager.sh; fi;"

    # Delete logs
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$HOST "sudo rm -f cluster_logs.tar.gz "
fi

if [ -n "$DVMHOST" ]
then
    echo "[$(date +%Y%m%d%H%M%S)][INFO] About to collect VMD logs"

    echo "[$(date +%Y%m%d%H%M%S)][INFO] Uploading scripts"
    # scp -q -i $IDENTITYFILE common.sh $AZUREUSER@$DVMHOST:/home/$AZUREUSER/common.sh
    # ssh -tq -i $IDENTITYFILE $AZUREUSER@$DVMHOST "sudo chmod 744 common.sh;"
    # scp -q -i $IDENTITYFILE collectlogsdvm.sh $AZUREUSER@$DVMHOST:/home/$AZUREUSER/collectlogsdvm.sh
    # ssh -tq -i $IDENTITYFILE $AZUREUSER@$DVMHOST "sudo chmod 744 collectlogsdvm.sh; ./collectlogsdvm.sh;"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "curl -O $ARTIFACTSURL/diagnosis/collectlogsdvm.sh;"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "sudo chmod 744 collectlogsdvm.sh; ./collectlogsdvm.sh;"

    # Copy logs back to local machine
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Downloading logs"
    scp -q -i $IDENTITYFILE $AZUREUSER@$DVMHOST:"/home/$AZUREUSER/dvm_logs.tar.gz" $LOGFILEFOLDER/dvm_logs.tar.gz

    # Delete scripts
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Removing temp files from DVM"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$DVMHOST "if [ -f common.sh ]; then sudo rm -f common.sh; fi;"
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$DVMHOST "if [ -f collectlogsdvm.sh ]; then sudo rm -f collectlogsdvm.sh; fi;"

    # Delete logs
    ssh -tq -i $IDENTITYFILE $AZUREUSER@$DVMHOST "sudo rm -f dvm_logs.tar.gz"
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO] Done collecting Kubernetes logs"
echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found in this location: $LOGFILEFOLDER"