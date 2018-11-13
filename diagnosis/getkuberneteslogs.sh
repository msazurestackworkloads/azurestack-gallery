#! /bin/bash

function printUsage
{
    echo "      Usage:"    
    echo "      $FILENAME -i id_rsa -h 192.168.102.34 -u azureuser"    
    echo "      $FILENAME --identity-file id_rsa --user azureuser --vmdhost 192.168.102.32"   
    echo "      $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser --vmdhost 192.168.102.32"
    echo "      $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser --vmdhost 192.168.102.32 --force"
    echo  "" 
    echo "            -i, --identity-file                         the RSA Private Key filefile to connect the kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -h, --host                                  public ip or FQDN of the Kubernetes cluster master VM. The VM name starts with k8s-master- "
    echo "            -u, --user                                  user name of the Kubernetes cluster master VM "
    echo "            -d, --vmdhost                               public ip or FQDN of the DVM. The vm name start with vmd- "
    echo "            -f, --force                                 copy private key to kubernetes without prompting to user"
    exit 1
}

FILENAME=$0

# Handle the named parameters
while [[ "$#" -gt 0 ]]
do
case $1 in
    -i|--identity-file)
    IDENTITYFILE="$2"
    ;;
    -h|--host)
    HOST="$2"
    ;;
    -d|--vmdhost)
    DVMHOST="$2"
    ;;
    -u|--user)
    AZUREUSER="$2"
    ;;
    -f|--force)
    FORCE="Y"
    ;;
    *)
    echo ""    
    echo "Incorrect parameter $1"    
    echo ""
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
    echo "--user can not be empty"
    printUsage
fi

if [ -z "$IDENTITYFILE" ]
then
    echo "--identity-file can not be empty"
    printUsage
fi

if [ -z "$DVMHOST" -a -z "$HOST" ]
then
    echo "--vmdhost and --host can not both be empty"
    printUsage
fi

if [ -z "$FORCE" ]
then
    FORCE="N"
else
    echo "The private key will be copied into the Kubernetes master to collect logs"
fi

if [ ! -f $IDENTITYFILE ]
then
    echo "can not find identity-file at $IDENTITYFILE"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep "BEGIN RSA PRIVATE KEY" || { echo "The identity file $IDENTITYFILE is not a RSA Private Key file."; echo "The RSA private key file starts with -----BEGIN RSA PRIVATE KEY-----"; exit 1; }
fi


echo "identity-file: $IDENTITYFILE"
echo "host: $HOST"
echo "user: $AZUREUSER"
echo "vmdhost: $DVMHOST"

CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="KubernetesLogs$CURRENTDATE"
mkdir -p $LOGFILEFOLDER

if [ -n "$HOST" ]
then
    if [ "$FORCE" = "N" ]
    then
        read -p "The private key will be copied into the Kubernetes master VM $HOST to collect logs,  Continue (y/n)?" choice
        case "$choice" in 
        y|Y ) echo "Continue to collect logs";;
        n|N ) echo "Stop to collect logs";exit 0 ;;
        * ) echo "Invalid choice $choice and stop to collect logs"; exit 0;;
        esac
    fi

    IDENTITYFILEBACKUPPATH="/home/$AZUREUSER/IDENTITYFILEBACKUP"

    # Remove existing scrit if ther is
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/collectlogsmanager.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogsmanager.sh; fi;"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/collectlogs.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogs.sh; fi;"

    #Backup id_rsa
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/.ssh/id_rsa ]; then mkdir -p $IDENTITYFILEBACKUPPATH;  sudo mv /home/$AZUREUSER/.ssh/id_rsa $IDENTITYFILEBACKUPPATH; fi;"

    #Copy id_rsa into Kubernete Host VM
    scp -i $IDENTITYFILE $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/.ssh/id_rsa

    #set up permission and  Download the script
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/.ssh/id_rsa ]; then sudo chmod 400 /home/$AZUREUSER/.ssh/id_rsa; cd /home/$AZUREUSER; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogsmanager.sh; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogs.sh ;sudo chmod 744 collectlogsmanager.sh;  fi;"

    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "cd /home/$AZUREUSER; ./collectlogsmanager.sh;"

    #Copy logs back to local machine
    scp -r -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/kubernetesalllogs $LOGFILEFOLDER

    #Restore id_rsa
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f $IDENTITYFILEBACKUPPATH/id_rsa ] ; then sudo mv $IDENTITYFILEBACKUPPATH/id_rsa /home/$AZUREUSER/.ssh/id_rsa; sudo rm -r -f $IDENTITYFILEBACKUPPATH; fi;"

    # Delete scrits
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/collectlogsmanager.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogsmanager.sh; fi;"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/collectlogs.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogs.sh; fi;"

    # Delete logs
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -d /home/$AZUREUSER/kubernetesalllogs ]; then sudo rm -f -r /home/$AZUREUSER/kubernetesalllogs; fi;"
fi

if [ -n "$DVMHOST" ]
then
    # Remove existing scrit if ther is
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "if [ -f /home/$AZUREUSER/collectlogsdvm.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogsdvm.sh; fi;"

    # Collect the logs
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "cd /home/$AZUREUSER; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogsdvm.sh; sudo chmod 744 collectlogsdvm.sh; ./collectlogsdvm.sh;"

    #Copy logs back to local machine
    scp -r -i $IDENTITYFILE $AZUREUSER@$DVMHOST:/home/$AZUREUSER/dvmlogs $LOGFILEFOLDER

    # Delete scrits
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "if [ -f /home/$AZUREUSER/collectlogsdvm.sh ]; then sudo rm -f /home/$AZUREUSER/collectlogsdvm.sh; fi;"

    # Delete logs
    ssh -t -i $IDENTITYFILE $AZUREUSER@$DVMHOST "if [ -d /home/$AZUREUSER/dvmlogs ]; then sudo rm -f -r /home/$AZUREUSER/dvmlogs; fi;"
fi
echo "Kubernetes logs are copied into $LOGFILEFOLDER"

