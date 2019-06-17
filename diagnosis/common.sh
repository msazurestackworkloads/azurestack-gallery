#! /bin/bash

RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
YELLOW='\033[0;33m'  # For crucial check success
NC='\033[0m'        # No color, back to normal

###
#   <summary>
#       Wrapper around the echo command that prints a message in the approprite color and log level
#   </summary>
#   <param name="1">Log level</param>
#   <param name="2">Message</param>
###
OUTPUT_LOCATION=${1:-"output"}
SCRIPT_NAME=${2:-"script"}
NOW=`date +%Y%m%d%H%M%S`
CURRENTDATE=$(date +"%Y-%m-%d-%H-%M-%S-%3N")
ERRFILENAME="$OUTPUT_LOCATION/$SCRIPT_NAME-Error-$CURRENTDATE.txt"
TRACEFILENAME="$OUTPUT_LOCATION/$SCRIPT_NAME-Log-$CURRENTDATE.txt"

log_level()
{
    case "$1" in
        -e) echo -e "${RED} $(date) [Err]  " ${@:2} | tee -a $ERRFILENAME
        ;;
        -w) echo -e "${YELLOW} $(date) [Warn] " ${@:2} | tee -a $TRACEFILENAME
        ;;
        -i) echo -e "${GREEN} $(date) [Info] " ${@:2} | tee -a $TRACEFILENAME
        ;;
        *)  echo -e "${NC} $(date) [Debug] " ${@:2} | tee -a $TRACEFILENAME
        ;;
    esac
}

is_master_node()
{
    if [[ $HOSTNAME == k8s-master* ]]; then
        return 0
    else
        return 1
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source file does not exist.
#   </summary>
#   <param name="1">Source file expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_file()
{
    if [ -f $1 ]; then
        sudo cp $1 $2/
    else
        log_level -e "Expected file not found: $1"
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_directory()
{
    if [ -d $1 ]; then
        sudo cp -r $1 $2/
    else
        log_level -e "Expected directory not found: $1"
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_directory_content()
{
    if [ -d $1 ]; then
        for f in $1/*
        do
            sudo cp -r $f $2/
        done
    else
        log_level -e "Expected directory not found: $1"
    fi
}

###
#   <summary>
#       Wrapper around the find command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination file</param>
###
try_print_directory_tree()
{
    if [ -d $1 ]; then
        sudo find $1 &> $2
    else
        log_level -w "Expected directory not found: $1"
    fi
}

###
#   <summary>
#       Look for known errors on CustomScriptExtension logs
#   </summary>
#   <param name="1">CustomScriptExtension logs location</param>
###
find_cse_errors()
{
    if [ -f $1 ];
    then
        log_level -i "File $1 found checking for errors"
        ERROR=`grep "VMExtensionProvisioningError" $1 -A 1 | tail -n 1`
        
        if [ "$ERROR" ]; then
            log_level -w "===================="
            log_level -e "[VMExtensionProvisioningError] $ERROR"
            log_level -e " Hint: The list of error codes can be found here: https://github.com/Azure/aks-engine/blob/master/parts/k8s/kubernetesprovisionsource.sh"
            log_level -e " Log file source: $1"
        fi
    else
        log_level -e "File $1 not found"
    fi
}

###
#   <summary>
#       Look for known errors on DVM logs
#   </summary>
#   <param name="1">DVM logs location</param>
###
find_spn_errors()
{
    if [ -f $1 ];
    then
        log_level -i "File $1 found checking for errors"
        ERROR403=$(grep "failed to load apimodel" $1 | grep "StatusCode=403")
        
        if [ "$ERROR403" ]; then
            log_level -e "===================="
            log_level -e "[AuthorizationFailed] $ERROR403"
            log_level -e " Hint: Double-check the entered Service Principal has write permissions to the target subscription"
            log_level -e " Help: https://aka.ms/AzsK8sSpn"
            log_level -e " Log file source: $1"
        fi
        
        ERROR401=$(grep "failed to load apimodel" $1 | grep "StatusCode=401" | grep "invalid_client")
        
        if [ "$ERROR401" ]; then
            log_level -e "===================="
            log_level -e "[InvalidClient] $ERROR401"
            log_level -e " Hint: double-check the entered Service Principal secret is correct"
            log_level -e " Log file source: $1"
        fi
        
        ERROR400=$(grep "failed to load apimodel" $1 | grep "StatusCode=400" | grep "unauthorized_client")
        
        if [ "$ERROR400" ]; then
            log_level -e "===================="
            log_level -e "[InvalidClient] $ERROR400"
            log_level -e " Hint: double-check the entered Service Principal name is correct"
            log_level -e " Log file source: $1"
        fi
    else
        log_level -e "File $1 not found"
    fi
}

###
#   <summary>
#       Look for known errors with etcd certs
#   </summary>
#   <param name="1">CustomScriptExtension logs location</param>
#   <param name="2">etcd status log</param>
###
find_etcd_bad_cert_errors()
{
    if [ -f $1 -a -f $2 ]
    then
        log_level -i "File $1 and $2 found checking for errors"
        STATUS14=`grep "command terminated with exit status=14" $1`
        BAD_CERT=`grep "remote error: tls: bad certificate" $2`
        
        if [ "$STATUS14" -a "$BAD_CERT" ]
        then
            TRUSTED_HOSTS=`openssl x509 -in /etc/kubernetes/certs/etcdpeer*.crt -text -noout | grep "X509v3 Subject Alternative Name" -A 1 | tail -n 1 | xargs`
            
            echo "===================="
            log_level -w "[TlsBadEtcdCertificate] $ERROR"
            log_level -w " Hint: The etcd instance running on $HOSTNAME cannot establish a secure connection with its peers."
            log_level -w " These are the trusted hosts as listed in certificate /etc/kubernetes/certs/etcdpeer[0-9].crt: "$TRUSTED_HOSTS"."
            log_level -w " Make sure the etcd peers are running on trusted hosts."
            log_level -w " Log file source 1: $1"
            log_level -w " Log file source 2: $2"
        fi
    else
        log_level -e "File $1 or $2 not found"
    fi
}
