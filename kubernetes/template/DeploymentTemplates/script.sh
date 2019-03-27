#!/bin/bash -e

ERR_APT_INSTALL_TIMEOUT=9 # Timeout installing required apt packages
ERR_AKSE_DOWNLOAD=10 # Failure downloading AKS-Engine binaries
ERR_AKSE_GENERATE=11 # Failure calling AKS-Engine's generate operation
ERR_AKSE_DEPLOY=12 # Failure calling AKS-Engine's deploy operation
ERR_CACERT_INSTALL=20 # Failure moving CA certificate
ERR_MS_GPG_KEY_DOWNLOAD_TIMEOUT=26 # Timeout waiting for Microsoft's GPG key download
ERR_METADATA_ENDPOINT=30 # Failure calling the metadata endpoint
ERR_API_MODEL=40 # Failure building API model using user input
ERR_AZS_CLOUD_REGISTER=50 # Failure calling az cloud register
ERR_AZS_CLOUD_ENVIRONMENT=51 # Failure setting az cloud environment
ERR_AZS_CLOUD_PROFILE=52 # Failure setting az cloud profile
ERR_AZS_LOGIN_AAD=53 # Failure to log in to AAD environment
ERR_AZS_LOGIN_ADFS=54 # Failure to log in to ADFS environment
ERR_AZS_ACCOUNT_SUB=55 # Failure setting account default subscription
ERR_APT_UPDATE_TIMEOUT=99 # Timeout waiting for apt-get update to complete

function collect_deployment_and_operations
{
    # Store main exit code
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ]; then
        log_level -i "CustomScript extension failed with exit code $EXIT_CODE"
    fi
    
    if ! command az 1> /dev/null; then
        log_level -w "Won't collect deployment logs, azure-cli is not installed"
        exit $EXIT_CODE
    fi
    
    if ! az account show -o none 2> /dev/null; then
        log_level -w "Won't collect deployment logs, azure-cli is not logged in"
        exit $EXIT_CODE
    fi
    
    log_level -i "Collecting deployment logs."
    
    DEPLOYLOGSDIR=/var/log/azure/arm-deployments
    mkdir -p $DEPLOYLOGSDIR
    
    DEPLOYMENTS=$(az group deployment list --resource-group $RESOURCE_GROUP_NAME --query '[].name' --output tsv)
    
    for deploy in $DEPLOYMENTS; do
        az group deployment show --resource-group $RESOURCE_GROUP_NAME --name $deploy | tee $DEPLOYLOGSDIR/$deploy.deploy > /dev/null
        az group deployment operation list --resource-group $RESOURCE_GROUP_NAME --name $deploy | tee $DEPLOYLOGSDIR/$deploy.operations > /dev/null
    done
    
    chown -R $ADMIN_USERNAME:$ADMIN_USERNAME $DEPLOYLOGSDIR
    
    log_level -i "CustomScript extension run to completion."
    exit $EXIT_CODE
}

# Collect deployment logs always, even if the script ends with an error
trap collect_deployment_and_operations EXIT

###
#   <summary>
#       Logs output by prepending date and log level type(Error, warning, info or verbose).
#   </summary>
#   <param name="1">Type to log. (Valid values are: -e for error, -w for warning, -i for info, else verbose)</param>
#   <param name="...">Output echo string.</param>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
log_level()
{
    case "$1" in
        -e) echo "$(date) [Err]  " ${@:2}
        ;;
        -w) echo "$(date) [Warn] " ${@:2}
        ;;
        -i) echo "$(date) [Info] " ${@:2}
        ;;
        *)  echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

###
#   <summary>
#       Retry given command by given number of times in case we have hit any failure.
#   </summary>
#   <param name="1">Number of retries</param>
#   <param name="2">Wait time between attempts</param>
#   <param name="3">Command timeout</param>
#   <param name="...">Command to execute.</param>
###
retrycmd_if_failure()
{
    retries=$1; wait_sleep=$2; timeout=$3;
    shift && shift && shift;
    
    for i in $(seq 1 $retries); do
        timeout $timeout ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
        fi
    done
    
    log_level -i "Command executed $i time/s.";
}

###
#   <summary>
#      Validate if file exist and it has non zero bytes. If validation passes moves file to new location.
#   </summary>
#   <param name="1">Source File Name.</param>
#   <param name="2">Destination File Name.</param>
#   <returns>None</returns>
#   <exception>Can exit with error code 1 in case file does not exist or size is zero.</exception>
#   <remarks>Called within same scripts.</remarks>
###
validate_and_restore_cluster_definition()
{
    if [ ! -s $1 ]; then
        log_level -e "Cluster definition file '$1' does not exist or it is empty. An error happened while manipulating its json content."
        exit 1
    fi
    mv $1 $2
}

###
#   <summary>
#      Creates PEM & PFX files out of the SPN secret.
#   </summary>
#   <param name="1">Service principle secret.</param>
#   <param name="2">Certificate PFX file name.</param>
#   <param name="3">Certificate PEM file name.</param>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
convert_secret_to_cert()
{
    log_level -i "Generating PFX and PEM files."
    
    echo $1 | base64 --decode > cert.json
    
    cat cert.json | jq '.data' | tr -d \" | base64 --decode > $2
    PASSWORD=$(cat cert.json | jq '.password' | tr -d \")
    
    openssl pkcs12 -in $2 -nodes -passin pass:$PASSWORD -out $3
}

###
#   <summary>
#       Copies Azure Stack root certificate to the appropriate store.
#   </summary>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
ensure_certificates()
{
    log_level -i "Moving certificates to appropriate store"
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
    AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"
    
    log_level -i "Copy ca-cert from '$AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH' to '$AZURESTACK_ROOT_CERTIFICATE_DEST_PATH' "
    cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH
    
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT"
    
    AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT"
    
    update-ca-certificates
    
    # Required by Azure CLI
    export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    echo "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" | tee -a /etc/environment > /dev/null
    
    if [ $IDENTITY_SYSTEM == "ADFS" ]; then
        # Trim "adfs" suffix
        ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA | jq '.authentication.loginEndpoint' | xargs | sed -e 's/adfs*$//' | xargs`
        log_level -i "ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"
        
        CERTIFICATE_PFX_LOCATION="spnauth.pfx"
        CERTIFICATE_PEM_LOCATION="spnauth.pem"
        
        convert_secret_to_cert $SPN_CLIENT_SECRET $CERTIFICATE_PFX_LOCATION $CERTIFICATE_PEM_LOCATION
        
        log_level -i "PFX path: '$CERTIFICATE_PFX_LOCATION'"
        log_level -i "PEM path: '$CERTIFICATE_PEM_LOCATION'"
    fi
}

# Add azure-cli apt source
add_azurecli_source()
{
    # https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#connect-to-azure-stack
    # https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
    
    log_level -i "Adding azure-cli apt source."
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list
    
    log_level -i "Downloading the Microsoft signing key."
    RECV_KEY=BC528686B50D79E339D3721CEB3E94ADBE1229CF
    retrycmd_if_failure 5 10 60 apt-key \
    --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
    --keyserver packages.microsoft.com \
    --recv-keys $RECV_KEY \
    || exit $ERR_MS_GPG_KEY_DOWNLOAD_TIMEOUT
}

# Clone msazurestackworkloads' AKSe fork and move relevant files to the working directory
download_akse()
{
    # Todo update release branch details: msazurestackworkloads, azsmaster
    retrycmd_if_failure 5 10 60 git clone https://github.com/msazurestackworkloads/aks-engine -b azsmaster || exit $ERR_AKSE_DOWNLOAD
    
    mkdir -p ./bin
    tar -zxvf aks-engine/examples/azurestack/aks-engine.tgz -C ./bin
    
    AKSE_LOCATION=./bin/aks-engine
    if [ ! -f $AKSE_LOCATION ]; then
        log_level -e "aks-engine binary not found in expected location"
        log_level -e "Expected location: $AKSE_LOCATION"
        exit 1
    fi
    
    DEFINITION_TEMPLATE=./aks-engine/examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json
    if [ ! -f $DEFINITION_TEMPLATE ]; then
        log_level -e "API model template for Kubernetes $K8S_AZURE_CLOUDPROVIDER_VERSION not found in expected location"
        log_level -e "Expected location: $DEFINITION_TEMPLATE"
        exit 1
    fi
    
    if [ ! -s $DEFINITION_TEMPLATE ]; then
        log_level -e "Downloaded API model template for Kubernetes $K8S_AZURE_CLOUDPROVIDER_VERSION is an empty file."
        log_level -e "Template location: $DEFINITION_TEMPLATE"
        exit 1
    fi
    
    cp $DEFINITION_TEMPLATE $AZURESTACK_CONFIGURATION
    
    log_level -i "aks-engine binary available in path $PWD/bin/aks-engine."
    log_level -i "API model template available in path $AZURESTACK_CONFIGURATION."
}

# Avoid apt failures by first checking if the lock files are around
# Function taken from the AKSe's code based
wait_for_apt_locks()
{
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo 'Waiting for release of apt locks'
        sleep 3
    done
}

# Avoid transcient apt-update failures
# Function taken from the AKSe's code based
apt_get_update()
{
    log_level -i "Updating apt cache."
    
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        dpkg --configure -a
        apt-get -f -y install
        apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
        [ $? -ne 0  ] && cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep 30
        fi
    done
    
    echo "Executed apt-get update $i time/s"
    wait_for_apt_locks
}

# Avoid transcient apt-install failures
# Function taken from the AKSe's code based
apt_get_install()
{
    retries=$1; wait_sleep=$2; timeout=$3;
    shift && shift && shift
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        dpkg --configure -a
        apt-get install --no-install-recommends -y ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    
    echo "Executed apt-get install --no-install-recommends -y \"$@\" $i times";
    wait_for_apt_locks
}

#####################################################################################
# start

log_level -i "Starting Kubernetes cluster deployment."
log_level -i "Running script as:  $(whoami)"
log_level -i "System information: $(uname -a)"

log_level -i "------------------------------------------------------------------------"
log_level -i "ARM parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "ADMIN_USERNAME:                           $ADMIN_USERNAME"
log_level -i "AGENT_COUNT:                              $AGENT_COUNT"
log_level -i "AGENT_SIZE:                               $AGENT_SIZE"
log_level -i "IDENTITY_SYSTEM:                          $IDENTITY_SYSTEM"
log_level -i "K8S_AZURE_CLOUDPROVIDER_VERSION:          $K8S_AZURE_CLOUDPROVIDER_VERSION"
log_level -i "MASTER_COUNT:                             $MASTER_COUNT"
log_level -i "MASTER_DNS_PREFIX:                        $MASTER_DNS_PREFIX"
log_level -i "MASTER_SIZE:                              $MASTER_SIZE"
log_level -i "PUBLICIP_DNS:                             $PUBLICIP_DNS"
log_level -i "PUBLICIP_FQDN:                            $PUBLICIP_FQDN"
log_level -i "REGION_NAME:                              $REGION_NAME"
log_level -i "RESOURCE_GROUP_NAME:                      $RESOURCE_GROUP_NAME"
log_level -i "SSH_PUBLICKEY:                            ----"
log_level -i "STORAGE_PROFILE:                          $STORAGE_PROFILE"
log_level -i "TENANT_ID:                                $TENANT_ID"
log_level -i "TENANT_SUBSCRIPTION_ID:                   $TENANT_SUBSCRIPTION_ID"

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    log_level -i "SPN_CLIENT_SECRET_KEYVAULT_ID:            $SPN_CLIENT_SECRET_KEYVAULT_ID"
    log_level -i "SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME:   $SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME"
else
    log_level -i "SPN_CLIENT_ID:                            ----"
    log_level -i "SPN_CLIENT_SECRET:                        ----"
fi

log_level -i "------------------------------------------------------------------------"
log_level -i "Constants"
log_level -i "------------------------------------------------------------------------"

ENVIRONMENT_NAME=AzureStackCloud
HYBRID_PROFILE=2018-03-01-hybrid

log_level -i "ENVIRONMENT_NAME: $ENVIRONMENT_NAME"
log_level -i "HYBRID_PROFILE:   $HYBRID_PROFILE"

log_level -i "------------------------------------------------------------------------"
log_level -i "Inner variables"
log_level -i "------------------------------------------------------------------------"

EXTERNAL_FQDN="${PUBLICIP_FQDN//$PUBLICIP_DNS.$REGION_NAME.cloudapp.}"
TENANT_ENDPOINT="https://management.$REGION_NAME.$EXTERNAL_FQDN"
SUFFIXES_STORAGE_ENDPOINT=$REGION_NAME.$EXTERNAL_FQDN
SUFFIXES_KEYVAULT_DNS=.vault.$REGION_NAME.$EXTERNAL_FQDN
FQDN_ENDPOINT_SUFFIX=cloudapp.$EXTERNAL_FQDN
AZURESTACK_RESOURCE_METADATA_ENDPOINT="$TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01"
STORAGE_PROFILE="${STORAGE_PROFILE:-blobdisk}"

log_level -i "EXTERNAL_FQDN:                            $EXTERNAL_FQDN"
log_level -i "TENANT_ENDPOINT:                          $TENANT_ENDPOINT"
log_level -i "SUFFIXES_STORAGE_ENDPOINT:                $SUFFIXES_STORAGE_ENDPOINT"
log_level -i "SUFFIXES_KEYVAULT_DNS:                    $SUFFIXES_KEYVAULT_DNS"
log_level -i "FQDN_ENDPOINT_SUFFIX:                     $FQDN_ENDPOINT_SUFFIX"
log_level -i "ENVIRONMENT_NAME:                         $ENVIRONMENT_NAME"
log_level -i "AZURESTACK_RESOURCE_METADATA_ENDPOINT:    $AZURESTACK_RESOURCE_METADATA_ENDPOINT"
log_level -i "STORAGE_PROFILE:                          $STORAGE_PROFILE"
log_level -i "------------------------------------------------------------------------"

WAIT_TIME_SECONDS=20
log_level -i "Waiting for $WAIT_TIME_SECONDS seconds to allow the system to stabilize.";
sleep $WAIT_TIME_SECONDS

#####################################################################################
# apt packages

log_level -i "Configuring azure-cli source."
add_azurecli_source

log_level -i "Updating apt cache."
apt_get_update || exit $ERR_APT_UPDATE_TIMEOUT

log_level -i "Installing azure-cli and dependencies."
apt_get_install 30 1 600  \
pax \
jq \
curl \
apt-transport-https \
lsb-release \
software-properties-common \
dirmngr \
azure-cli \
|| exit $ERR_APT_INSTALL_TIMEOUT

log_level -i "Azure CLI version: $(az --version)"

#####################################################################################
# aks-engine

log_level -i "Downloading AKS-Engine binary and cluster definition templates"

mkdir -p $PWD/bin

AZURESTACK_CONFIGURATION=$PWD/bin/azurestack.json
AZURESTACK_CONFIGURATION_TEMP=$PWD/bin/azurestack.tmp

download_akse || exit $ERR_AKSE_DOWNLOAD

#####################################################################################
# certificates

log_level -i "Moving certificates to the expected locations as required by azure-cli and AKSe"
ensure_certificates || exit $ERR_CACERT_INSTALL

#####################################################################################
# apimodel values

log_level -i "Computing cluster definition values."

METADATA=`curl -s -f --retry 10 $AZURESTACK_RESOURCE_METADATA_ENDPOINT` || exit $ERR_METADATA_ENDPOINT
ENDPOINT_GRAPH_ENDPOINT=`echo $METADATA | jq '.graphEndpoint' | xargs`
ENDPOINT_GALLERY=`echo $METADATA | jq '.galleryEndpoint' | xargs`
ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=`echo $METADATA | jq '.authentication.audiences'[0] | xargs`

log_level -i "ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID: $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID"

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    # Trim "adfs" suffix
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA | jq '.authentication.loginEndpoint' | xargs | sed -e 's/adfs*$//' | xargs`
else
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA | jq '.authentication.loginEndpoint' | xargs`
fi

log_level -i "ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"

#####################################################################################
# apimodel gen

log_level -i "Setting general cluster definition properties."

cat $AZURESTACK_CONFIGURATION | \
jq --arg ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID '.properties.customCloudProfile.environment.serviceManagementEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID'| \
jq --arg ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT '.properties.customCloudProfile.environment.activeDirectoryEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT' | \
jq --arg ENDPOINT_GRAPH_ENDPOINT $ENDPOINT_GRAPH_ENDPOINT '.properties.customCloudProfile.environment.graphEndpoint = $ENDPOINT_GRAPH_ENDPOINT' | \
jq --arg TENANT_ENDPOINT $TENANT_ENDPOINT '.properties.customCloudProfile.environment.resourceManagerEndpoint = $TENANT_ENDPOINT' | \
jq --arg ENDPOINT_GALLERY $ENDPOINT_GALLERY '.properties.customCloudProfile.environment.galleryEndpoint = $ENDPOINT_GALLERY' | \
jq --arg SUFFIXES_STORAGE_ENDPOINT $SUFFIXES_STORAGE_ENDPOINT '.properties.customCloudProfile.environment.storageEndpointSuffix = $SUFFIXES_STORAGE_ENDPOINT' | \
jq --arg SUFFIXES_KEYVAULT_DNS $SUFFIXES_KEYVAULT_DNS '.properties.customCloudProfile.environment.keyVaultDNSSuffix = $SUFFIXES_KEYVAULT_DNS' | \
jq --arg FQDN_ENDPOINT_SUFFIX $FQDN_ENDPOINT_SUFFIX '.properties.customCloudProfile.environment.resourceManagerVMDNSSuffix = $FQDN_ENDPOINT_SUFFIX' | \
jq --arg REGION_NAME $REGION_NAME '.location = $REGION_NAME' | \
jq --arg MASTER_DNS_PREFIX $MASTER_DNS_PREFIX '.properties.masterProfile.dnsPrefix = $MASTER_DNS_PREFIX' | \
jq '.properties.agentPoolProfiles[0].count'=$AGENT_COUNT | \
jq --arg AGENT_SIZE $AGENT_SIZE '.properties.agentPoolProfiles[0].vmSize=$AGENT_SIZE' | \
jq '.properties.masterProfile.count'=$MASTER_COUNT | \
jq --arg MASTER_SIZE $MASTER_SIZE '.properties.masterProfile.vmSize=$MASTER_SIZE' | \
jq --arg ADMIN_USERNAME $ADMIN_USERNAME '.properties.linuxProfile.adminUsername = $ADMIN_USERNAME' | \
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' \
> $AZURESTACK_CONFIGURATION_TEMP

validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL

if [ "$STORAGE_PROFILE" == "blobdisk" ]; then
    log_level -w "Using blob disks requires AvailabilitySet, overriding availabilityProfile and storageProfile."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg AvailabilitySet "AvailabilitySet" '.properties.agentPoolProfiles[0].availabilityProfile=$AvailabilitySet' | \
    jq --arg StorageAccount "StorageAccount" '.properties.agentPoolProfiles[0].storageProfile=$StorageAccount' | \
    jq --arg StorageAccount "StorageAccount" '.properties.masterProfile.storageProfile=$StorageAccount' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
fi

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    log_level -i "Setting ADFS specific cluster definition properties."
    ADFS="adfs"
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg ADFS $ADFS '.properties.customCloudProfile.identitySystem=$ADFS' | \
    jq --arg authenticationMethod "client_certificate" '.properties.customCloudProfile.authenticationMethod=$authenticationMethod' | \
    jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
    jq --arg SPN_CLIENT_SECRET_KEYVAULT_ID $SPN_CLIENT_SECRET_KEYVAULT_ID '.properties.servicePrincipalProfile.keyvaultSecretRef.vaultID = $SPN_CLIENT_SECRET_KEYVAULT_ID' | \
    jq --arg SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME $SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME '.properties.servicePrincipalProfile.keyvaultSecretRef.secretName = $SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME' \
    > $AZURESTACK_CONFIGURATION_TEMP
else
    log_level -i "Setting AAD specific cluster definition properties."
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
    jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' \
    > $AZURESTACK_CONFIGURATION_TEMP
fi

validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL

log_level -i "Done building cluster definition."

#####################################################################################
# azure-cli cloud
# https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#connect-to-azure-stack

# azure-cli needs the "adfs" suffix
if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=${ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT}adfs;
fi;

log_level -i "Registering to Azure Stack cloud."
retrycmd_if_failure 5 10 60 az cloud register \
-n $ENVIRONMENT_NAME \
--endpoint-resource-manager $TENANT_ENDPOINT \
--suffix-storage-endpoint $SUFFIXES_STORAGE_ENDPOINT \
--suffix-keyvault-dns $SUFFIXES_KEYVAULT_DNS \
--endpoint-active-directory-resource-id $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID \
--endpoint-active-directory $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT \
--endpoint-active-directory-graph-resource-id $ENDPOINT_GRAPH_ENDPOINT || exit $ERR_AZS_CLOUD_REGISTER

log_level -i "Setting Azure Stack environment."
retrycmd_if_failure 5 10 60 az cloud set -n $ENVIRONMENT_NAME || exit $ERR_AZS_CLOUD_ENVIRONMENT

log_level -i "Updating cloud profile with value: $HYBRID_PROFILE."
retrycmd_if_failure 5 10 60 az cloud update --profile $HYBRID_PROFILE || exit $ERR_AZS_CLOUD_PROFILE

#####################################################################################
# azure-cli login

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    log_level -i "Login to ADFS environment using Azure CLI."
    retrycmd_if_failure 5 10 60 az login \
    --service-principal -u $SPN_CLIENT_ID -p $CERTIFICATE_PEM_LOCATION \
    --tenant $TENANT_ID \
    --output none \
    || exit $ERR_AZS_LOGIN_ADFS
else
    log_level -i "Login to AAD environment using Azure CLI."
    retrycmd_if_failure 5 10 60 az login \
    --service-principal -u $SPN_CLIENT_ID -p $SPN_CLIENT_SECRET \
    --tenant $TENANT_ID \
    --output none \
    || exit $ERR_AZS_LOGIN_AAD
fi

log_level -i "Setting subscription to $TENANT_SUBSCRIPTION_ID"
retrycmd_if_failure 5 10 60 az account set --subscription $TENANT_SUBSCRIPTION_ID --output none || exit $ERR_AZS_ACCOUNT_SUB

#####################################################################################
# aks-engine commands

log_level -i "Generating ARM template using AKS-Engine."
# No retry, generate does not call any external endpoint
./bin/aks-engine generate $AZURESTACK_CONFIGURATION || exit $ERR_AKSE_GENERATE

log_level -i "ARM template saved in directory $PWD/_output/$MASTER_DNS_PREFIX."

log_level -i "Deploying the template."
retrycmd_if_failure 3 10 6000 az group deployment create \
-g $RESOURCE_GROUP_NAME \
--template-file _output/$MASTER_DNS_PREFIX/azuredeploy.json \
--parameters _output/$MASTER_DNS_PREFIX/azuredeploy.parameters.json \
--output none  \
|| exit $ERR_AKSE_DEPLOY

log_level -i "Kubernetes cluster deployment complete."