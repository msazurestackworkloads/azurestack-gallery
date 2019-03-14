#! /bin/bash

ERRFILENAME=$1

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
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected file not found: $1" | tee -a $ERRFILENAME
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
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
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
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
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
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
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
        ERROR=`grep "VMExtensionProvisioningError" $1 -A 1 | tail -n 1`
        
        if [ "$ERROR" ]; then
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME][VMExtensionProvisioningError] $ERROR" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: The list of error codes can be found here: https://github.com/Azure/aks-engine/blob/master/parts/k8s/kubernetesprovisionsource.sh" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Log file source: $1" | tee -a $ERRFILENAME
        fi
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
        ERROR403=$(grep "failed to load apimodel" $1 | grep "StatusCode=403")
        
        if [ "$ERROR403" ]; then
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME][AuthorizationFailed] $ERROR403" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: Double-check the entered Service Principal has write permissions to the target subscription (contributor role)" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Help: https://aka.ms/AzsK8sSpn" | tee -a $ERRFILENAME        
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Log file source: $1" | tee -a $ERRFILENAME
        fi

        ERROR401=$(grep "failed to load apimodel" $1 | grep "StatusCode=401" | grep "invalid_client")
        
        if [ "$ERROR401" ]; then
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME][InvalidClient] $ERROR401" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: double-check the entered Service Principal secret is correct" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Log file source: $1" | tee -a $ERRFILENAME
        fi

        ERROR400=$(grep "failed to load apimodel" $1 | grep "StatusCode=400" | grep "unauthorized_client")
        
        if [ "$ERROR400" ]; then
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME][InvalidClient] $ERROR400" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: double-check the entered Service Principal name is correct" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Log file source: $1" | tee -a $ERRFILENAME
        fi

        ERROR400=$(grep "unauthorized_client" $1 | grep "Application with identifier" | grep "was not found in the directory")
        
        if [ "$ERROR400" ]; then
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME][AuthorizationFailed] $ERROR400" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: double-check the entered Service Principal has access to the subscription" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Help: https://aka.ms/AzsK8sSpn" | tee -a $ERRFILENAME        
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Log file source: $1" | tee -a $ERRFILENAME
        fi
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
        STATUS14=`grep "command terminated with exit status=14" $1` 
        BAD_CERT=`grep "remote error: tls: bad certificate" $2` 
        
        if [ "$STATUS14" -a "$BAD_CERT" ]
        then
            TRUSTED_HOSTS=`openssl x509 -in /etc/kubernetes/certs/etcdpeer*.crt -text -noout | grep "X509v3 Subject Alternative Name" -A 1 | tail -n 1 | xargs`
            
            echo "====================" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME][TlsBadEtcdCertificate] $ERROR" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Hint: The etcd instance running on $HOSTNAME cannot establish a secure connection with its peers." | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] These are the trusted hosts as listed in certificate /etc/kubernetes/certs/etcdpeer[0-9].crt: "$TRUSTED_HOSTS"." | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Make sure the etcd peers are running on trusted hosts." | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Log file source 1: $1" | tee -a $ERRFILENAME
            echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Log file source 2: $2" | tee -a $ERRFILENAME
        fi
    fi
}