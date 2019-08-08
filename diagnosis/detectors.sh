#!/bin/bash

ERRFILENAME=$1

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
            echo "[$(date +%Y%m%d%H%M%S)][ERROR][$HOSTNAME] Hint: Double-check the entered Service Principal has write permissions to the target subscription" | tee -a $ERRFILENAME
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
