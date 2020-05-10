#!/bin/bash

validateKeys()
{
    local user=$1
    local host=$2
    local flags=$3
    
    ssh ${flags} ${user}@${host} "exit"
    
    if [ $? -ne 0 ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERR] Error connecting to host ${host}"
        exit 1
    fi
}

processRegistryHost()
{
    local user=$1
    local host=$2
    local sshflags=$3
    local scpflags=$4
    local logfilefolder=$5
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Processing registry server ${host}"
    scp ${scpflags} collectlogs.sh ${user}@${host}:/home/${user}/collectlogs.sh
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting logs from registry server ${host}"
    ssh ${sshflags} ${user}@${host} "sudo chmod 744 collectlogs.sh; ./collectlogs.sh containerregistry;"
    scp ${scpflags} ${user}@${host}:/home/${user}/containerregistry.zip ${logfilefolder}/
    ssh ${sshflags} ${user}@${host} "rm -f -r collectlogs.sh containerregistry.zip"
}

printUsage()
{
    echo "$0 collects diagnostics from registry"
    echo ""
    echo "Usage:"
    echo "  $0 [flags]"
    echo ""
    echo "Flags:"
    echo "  -u, --user                        The administrator username for the registry server."
    echo "  -i, --identity-file               RSA private key tied to the public key used to create registry server vm (usually named 'id_rsa')"
    echo "  -r, --registry-server-IP          Public IP address assign to registry server."
    echo "      --disable-host-key-checking   Sets SSH's StrictHostKeyChecking option to \"no\" while the script executes. Only use in a safe environment."
    echo "  -h, --help                        Print script usage"
    echo ""
    echo "Examples:"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -u azureuser --disable-host-key-checking"
    echo "  $0 -u azureuser -i ~/.ssh/id_rsa -u azureuser -r 10.10.10.10"
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
            shift 2
        ;;
        -u|--user)
            USER="$2"
            shift 2
        ;;
        -r|--registry-server-name)
            REGISTRY_HOST="$2"
            shift 2
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

if [ -z "$REGISTRY_HOST" ]
then
    echo ""
    echo "[ERR] --registry-server-name is required"
    printUsage
    exit 1
fi

# Print user input
echo ""
echo "user:                    $USER"
echo "identity-file:           $IDENTITYFILE"
echo "registry-server:         $REGISTRY_HOST"
echo ""

SSH_FLAGS="-q -t -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"
SCP_FLAGS="-q -i ${IDENTITYFILE} ${KNOWN_HOSTS_OPTIONS}"

echo "[$(date +%Y%m%d%H%M%S)][INFO] Checking connectivity with server "
validateKeys $USER ${REGISTRY_HOST} "${SSH_FLAGS}"

NOW=`date +%Y%m%d%H%M%S`
LOGFILEFOLDER="_output/log-${NOW}"
mkdir -p $LOGFILEFOLDER

processRegistryHost $USER ${REGISTRY_HOST} "${SSH_FLAGS}" "${SCP_FLAGS}" $LOGFILEFOLDER

echo "[$(date +%Y%m%d%H%M%S)][INFO] Logs can be found here: $LOGFILEFOLDER"
