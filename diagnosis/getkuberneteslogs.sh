#! /bin/bash

function printUsage
{
    echo "      Usage:"    
    echo "      $FILENAME -i id_rsa -h 192.168.102.34 -u azureuser"    
    echo "      $FILENAME --identity-file id_rsa --user azureuser --dvmhost 192.168.102.32"   
    echo "      $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser --dvmhost 192.168.102.32"   
    echo  "" 
    echo "            -i, --identity-file                         the private key file to connect the kubernetes master VM"
    echo "            -h, --host                                  public ip or FQDN of the Kubernetes cluster master VM. The VM name starts with k8s-master- "
    echo "            -u, --user                                  user name of the Kubernetes cluster master VM "
    echo "            -d, --dvmhost                               public ip or FQDN of the DVM. The vm name start with vhd- "
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
    -d|--dvmhost)
    DVMHOST="$2"
    ;;
    -u|--user)
    USER="$2"
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

if [ -z "$IDENTITYFILE" -o -z "$USER" ]
then
    printUsage
fi

if [ -z "$DVMHOST" -a -z "$HOST" ]
then
    printUsage
fi

echo "identity-file: $IDENTITYFILE"
echo "host: $HOST"
echo "user: $USER"
echo "dvmhost: $DVMHOST"

CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
LOGFILEFOLDER="KubernetesLogs$CURRENTDATE"
mkdir -p $LOGFILEFOLDER

if [ -n "$HOST" ]
then
    read -p "The private key will be copied into the Kubernetes master VM $HOST to collect logs,  Continue (y/n)?" choice
    case "$choice" in 
    y|Y ) echo "Continue to collect logs";;
    n|N ) echo "Stop to collect logs";exit 0 ;;
    * ) echo "Invalid choice $choice and stop to collect logs"; exit 0;;
    esac

    IDENTITYFILEBACKUPPATH="/home/$USER/IDENTITYFILEBACKUP"

    # Remove existing scrit if ther is
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/collectlogsmanager.sh ]; then sudo rm -f /home/$USER/collectlogsmanager.sh; fi;"
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/collectlogs.sh ]; then sudo rm -f /home/$USER/collectlogs.sh; fi;"

    #Backup id_rsa
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/.ssh/id_rsa ]; then mkdir -p $IDENTITYFILEBACKUPPATH;  sudo mv /home/$USER/.ssh/id_rsa $IDENTITYFILEBACKUPPATH; fi;"

    #Copy id_rsa into Kubernete Host VM
    scp -i $IDENTITYFILE $IDENTITYFILE $USER@$HOST:/home/$USER/.ssh/id_rsa

    #set up permission and  Download the script
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/.ssh/id_rsa ]; then sudo chmod 400 /home/$USER/.ssh/id_rsa; cd /home/$USER; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogsmanager.sh; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogs.sh ;sudo chmod 744 collectlogsmanager.sh;  fi;"

    ssh -t -i $IDENTITYFILE $USER@$HOST "cd /home/$USER; ./collectlogsmanager.sh;"

    #Copy logs back to local machine
    scp -r -i $IDENTITYFILE $USER@$HOST:/home/$USER/kubernetesalllogs $LOGFILEFOLDER

    #Restore id_rsa
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f $IDENTITYFILEBACKUPPATH/id_rsa ] ; then sudo mv $IDENTITYFILEBACKUPPATH/id_rsa /home/$USER/.ssh/id_rsa; sudo rm -r -f $IDENTITYFILEBACKUPPATH ; fi;"

    # Delete scrits
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/collectlogsmanager.sh ]; then sudo rm -f /home/$USER/collectlogsmanager.sh ; fi;"
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -f /home/$USER/collectlogs.sh ]; then sudo rm -f /home/$USER/collectlogs.sh; fi;"

    # Delete logs
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -d /home/$USER/kubernetesalllogs ]; then sudo rm -f -r /home/$USER/kubernetesalllogs ; fi;"
fi

if [ -n "$DVMHOST" ]
then
    # Remove existing scrit if ther is
    ssh -t -i $IDENTITYFILE $USER@$DVMHOST "if [ -f /home/$USER/collectlogsdvm.sh ]; then sudo rm -f /home/$USER/collectlogsdvm.sh; fi;"

    # Collect the logs
    ssh -t -i $IDENTITYFILE $USER@$DVMHOST "cd /home/$USER; curl -O https://raw.githubusercontent.com/msazurestackworkloads/azurestack-gallery/master/diagnosis/collectlogsdvm.sh; sudo chmod 744 collectlogsdvm.sh; ./collectlogsdvm.sh;"

    #Copy logs back to local machine
    scp -r -i $IDENTITYFILE $USER@$DVMHOST:/home/$USER/dvmlogs $LOGFILEFOLDER

    # Delete scrits
    ssh -t -i $IDENTITYFILE $USER@$DVMHOST "if [ -f /home/$USER/collectlogsdvm.sh ]; then sudo rm -f /home/$USER/collectlogsdvm.sh; fi;"

    # Delete logs
    ssh -t -i $IDENTITYFILE $USER@$HOST "if [ -d /home/$USER/dvmlogs ]; then sudo rm -f -r /home/$USER/kubernetesalllogs ; fi;"
fi
echo "Kubernetes logs are copied into $LOGFILEFOLDER"

