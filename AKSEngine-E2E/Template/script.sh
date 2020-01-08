#! /bin/bash -ex

ERR_APT_INSTALL_TIMEOUT=9           # Timeout installing required apt packages
ERR_AKSE_DOWNLOAD=10                # Failure downloading AKS-Engine binaries
ERR_AKSE_DEPLOY=12                  # Failure calling AKS-Engine's deploy operation
ERR_TEMPLATE_DOWNLOAD=13            # Failure downloading AKS-Engine template
ERR_INVALID_AGENT_COUNT_VALUE=14    # Both Windows and Linux agent value is zero
ERR_CACERT_INSTALL=20               # Failure moving CA certificate
ERR_METADATA_ENDPOINT=30            # Failure calling the metadata endpoint
ERR_API_MODEL=40                    # Failure building API model using user input
ERR_AZS_CLOUD_REGISTER=50           # Failure calling az cloud register
ERR_APT_UPDATE_TIMEOUT=99           # Timeout waiting for apt-get update to complete

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
        -e) echo "$(date) [Error]  : " ${@:2}
        ;;
        -w) echo "$(date) [Warning]: " ${@:2}
        ;;
        -i) echo "$(date) [Info]   : " ${@:2}
        ;;
        *)  echo "$(date) [Verbose]: " ${@:2}
        ;;
    esac
}

###
#   <summary>
#       Retry given command by given number of times in case we have hit any failure.
#   </summary>
#   <param name="1">Number of retry.</param>
#   <param name="2">Wait time between retry.</param>
#   <param name="...">Command to be executed.</param>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
retrycmd_if_failure()
{
    retries=$1;
    wait=$2;
    for i in $(seq 1 $retries); do
        ${@:3}; [ $? -eq 0  ] && break || sleep $wait;
    done;
    log_level -i "Command Executed $i times.";
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
check_and_move_azurestack_configuration() {
    
    if [ -s $1 ] ; then
        log_level -i "Found '$1' in path '$PWD' and is greater than zero bytes."
    else
        log_level -e "File '$1' does not exist in '$PWD' or is zero length. Error happend during building input API model or cluster definition."
        exit 1
    fi
    
    log_level -i "Moving file '$1' to '$2'"
    sudo mv $1 $2
    log_level -i "Completed creating API model file with given stamp information."
}

##
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
#       Copying AzureStack root certificate to appropriate store.
#   </summary>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
ensureCertificates()
{
    log_level -i "Updating certificates to appropriate store"
    
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
    AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"
    
    log_level -i "Copy cert from '$AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH' to '$AZURESTACK_ROOT_CERTIFICATE_DEST_PATH' "
    sudo cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH
    
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`
    AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`
    
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT"
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT"
    
    update-ca-certificates
    
    # Azure CLI specific changes.
    export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    sudo sed -i -e "\$aREQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" /etc/environment
    
    AZURESTACK_RESOURCE_METADATA_ENDPOINT="$TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01"
    curl $AZURESTACK_RESOURCE_METADATA_ENDPOINT
}

# Basic details of the system
log_level -i "Running  script as : $(whoami)"

log_level -i "System information: $(sudo uname -a)"
WAIT_TIME_SECONDS=20
log_level -i "Waiting for $WAIT_TIME_SECONDS seconds for system to get into stable state."
sleep $WAIT_TIME_SECONDS
#####################################################################################

log_level -i "------------------------------------------------------------------------"
log_level -i "ARM parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "ADMIN_USERNAME:                           $ADMIN_USERNAME"
log_level -i "AGENT_COUNT:                              $AGENT_COUNT"
log_level -i "AGENT_SIZE:                               $AGENT_SIZE"
log_level -i "AKSENGINE_API_MODEL:                      $AKSENGINE_API_MODEL"
log_level -i "AKSENGINE_BRANCH:                         $AKSENGINE_BRANCH"
log_level -i "AKSENGINE_NODE_COUNT:                     $AKSENGINE_NODE_COUNT"
log_level -i "AKSENGINE_REPO:                           $AKSENGINE_REPO"
log_level -i "AKSENGINE_UPGRADE_VERSION:                $AKSENGINE_UPGRADE_VERSION"
log_level -i "AVAILABILITY_PROFILE:                     $AVAILABILITY_PROFILE"
log_level -i "IDENTITY_SYSTEM:                          $IDENTITY_SYSTEM"
log_level -i "K8S_AZURE_CLOUDPROVIDER_VERSION:          $K8S_AZURE_CLOUDPROVIDER_VERSION"
log_level -i "MASTER_COUNT:                             $MASTER_COUNT"
log_level -i "MASTER_DNS_PREFIX:                        $MASTER_DNS_PREFIX"
log_level -i "MASTER_SIZE:                              $MASTER_SIZE"
log_level -i "NETWORK_PLUGIN:                           $NETWORK_PLUGIN"
log_level -i "PUBLICIP_DNS:                             $PUBLICIP_DNS"
log_level -i "PUBLICIP_FQDN:                            $PUBLICIP_FQDN"
log_level -i "REGION_NAME:                              $REGION_NAME"
log_level -i "RESOURCE_GROUP_NAME:                      $RESOURCE_GROUP_NAME"
log_level -i "SSH_PUBLICKEY:                            ----"
log_level -i "STORAGE_PROFILE:                          $STORAGE_PROFILE"
log_level -i "TENANT_ID:                                $TENANT_ID"
log_level -i "TENANT_SUBSCRIPTION_ID:                   $TENANT_SUBSCRIPTION_ID"
log_level -i "WINDOWS_ADMIN_PASSWORD:                   ----"
log_level -i "WINDOWS_ADMIN_USERNAME:                   $WINDOWS_ADMIN_USERNAME"
log_level -i "WINDOWS_AGENT_COUNT:                      $WINDOWS_AGENT_COUNT"
log_level -i "WINDOWS_AGENT_SIZE:                       $WINDOWS_AGENT_SIZE"


#####################################################################################
# Install pre-requisites

retrycmd_if_failure 5 10 sudo apt-get update -y
PACKAGES="make pax jq curl apt-transport-https lsb-release software-properties-common dirmngr"
retrycmd_if_failure 5 10 sudo apt-get install ${PACKAGES} -y

####################################################################################
#Section to install Azure CLI.
#https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#connect-to-azure-stack
#https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest

AZ_REPO=$(lsb_release -cs)
RECV_KEY=BC528686B50D79E339D3721CEB3E94ADBE1229CF

# Modify your sources list
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
sudo tee /etc/apt/sources.list.d/azure-cli.list

#Get Microsoft signing key
log_level -i "Get the Microsoft signing key."
retrycmd_if_failure 5 10 sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv --keyserver packages.microsoft.com --recv-keys $RECV_KEY

log_level -i "Update system again to latest."
retrycmd_if_failure 5 10 sudo apt-get update

log_level -i "Installing azure cli...."
retrycmd_if_failure 5 10 sudo apt-get install azure-cli

log_level -i "Azure CLI version : $(az --version)"

#####################################################################################
#Section to install Go.


ROOT_PATH=/home/azureuser
sudo mkdir $ROOT_PATH/bin
cd $ROOT_PATH
sudo wget https://dl.google.com/go/go1.13.4.linux-amd64.tar.gz
sudo tar -C  $ROOT_PATH/bin -xzf go1.13.4.linux-amd64.tar.gz

sudo apt install gcc make -y

#Set $HOME variable required for go version 1.12 or later
export HOME=/home/azureuser

# Set the environment variables
export GOPATH=/home/azureuser
export GOROOT=/home/azureuser/bin/go
export PATH=$GOPATH:$GOROOT/bin:$GOPATH/bin:$PATH


#####################################################################################
#Section to install/get AKS-Engine respository and definition template
log_level -i "Getting AKS-Engine respository"

# Todo update release branch details: msazurestackworkloads, azsmaster
retrycmd_if_failure 5 10 git clone https://github.com/$AKSENGINE_REPO -b $AKSENGINE_BRANCH

cd aks-engine
sudo mkdir -p $ROOT_PATH/src/github.com/Azure
sudo mv $ROOT_PATH/aks-engine $ROOT_PATH/src/github.com/Azure

#Section to get the apimodel file
log_level -i "Getting api model file"

sudo curl --retry 5 --retry-delay 10 --max-time 60 -s -f -O "$AKSENGINE_API_MODEL"
CONFIG_FILE_NAME="${AKSENGINE_API_MODEL##*/}"

AZURESTACK_CONFIGURATION=$ROOT_PATH/src/github.com/Azure/aks-engine/azurestack.json
AZURESTACK_CONFIGURATION_TEMP=$ROOT_PATH/src/github.com/Azure/aks-engine/azurestack.tmp

sudo cp $CONFIG_FILE_NAME $AZURESTACK_CONFIGURATION

if [ ! -f $AZURESTACK_CONFIGURATION ]; then
    log_level -e "API model template not found in expected location"
    log_level -e "Expected location: $AZURESTACK_CONFIGURATION"
    exit 1
fi

if [ ! -s $AZURESTACK_CONFIGURATION ]; then
    log_level -e "Downloaded API model template is an empty file."
    log_level -e "Template location: $AZURESTACK_CONFIGURATION"
    exit 1
fi

#####################################################################################
# Update certificates to right location as they are required
# for CLI and AKS to connect to Azure Stack

EXTERNAL_FQDN="${PUBLICIP_FQDN//$PUBLICIP_DNS.$REGION_NAME.cloudapp.}"
TENANT_ENDPOINT="https://management.$REGION_NAME.$EXTERNAL_FQDN"
SUFFIXES_STORAGE_ENDPOINT=$REGION_NAME.$EXTERNAL_FQDN
SUFFIXES_KEYVAULT_DNS=.vault.$REGION_NAME.$EXTERNAL_FQDN
FQDN_ENDPOINT_SUFFIX=cloudapp.$EXTERNAL_FQDN
ENVIRONMENT_NAME=AzureStackCloud
AUTHENTICATION_METHOD=client_secret


log_level -i "EXTERNAL_FQDN is:$EXTERNAL_FQDN"
log_level -i "TENANT_ENDPOINT is:$TENANT_ENDPOINT"

retrycmd_if_failure 20 30 ensureCertificates

#####################################################################################
# Make sure `k` is in the path
# https://github.com/Azure/aks-engine/blob/master/docs/community/developer-guide.md#end-to-end-tests

KUBECTL_VERSION=1.15.7

echo "==> Downloading kubectl version ${KUBECTL_VERSION} <=="
sudo curl -L https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl
sudo chmod +x /usr/local/bin/kubectl

sudo cp $ROOT_PATH/src/github.com/Azure/aks-engine/scripts/k /usr/local/bin/k
sudo chmod +x /usr/local/bin/k
export PATH=/usr/local/bin:$PATH

#####################################################################################
# Section to create API model file for AKS-Engine.

# First check if API model file exist else exit.

METADATA=`curl --retry 10 $TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01`
ENDPOINT_GRAPH_ENDPOINT=`echo $METADATA  | jq '.graphEndpoint' | tr -d \"`
ENDPOINT_GALLERY=`echo $METADATA  | jq '.galleryEndpoint' | tr -d \"`
ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=`echo $METADATA  | jq '.authentication.audiences'[0] | tr -d \"`
ENDPOINT_PORTAL=`echo $METADATA | jq '.portalEndpoint' | xargs`
log_level -i "Endpoint active directory resource id is: $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID."

if [ $IDENTITY_SYSTEM == "ADFS" ] ; then
    # Trim "adfs" from end of login endpoint if it is ADFS
    log_level -i "In ADFS section to get(Active_Directory_Endpoint, SPN_CLIENT_SECRET) configurations."
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA  | jq '.authentication.loginEndpoint' | tr -d \" | sed -e 's/adfs*$//' | tr -d \" `
    log_level -i "Active directory endpoint is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"
    
    log_level -i "Append adfs back to Active directory endpoint as it is required in Azure CLI to register and login."
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=${ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT}adfs
    log_level -i "Final ACTIVE_DIRECTORY endpoint value for adfs is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT."
    
else
    log_level -i "In AAD section to get(Active_Directory_Endpoint) configurations.."
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA  | jq '.authentication.loginEndpoint' | tr -d \"`
    log_level -i "Active directory endpoint is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"
fi

IDENTITY_SYSTEM_LOWER=`echo "$IDENTITY_SYSTEM" | tr '[:upper:]' '[:lower:]'`


#####################################################################################
# Section to generate ARM template using AKS Engine, login using Azure CLI and deploy the template.
# https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#connect-to-azure-stack
HYBRID_PROFILE=2018-03-01-hybrid
log_level -i "Register to AzureStack cloud using below command."
retrycmd_if_failure 5 10 az cloud register -n $ENVIRONMENT_NAME --endpoint-resource-manager $TENANT_ENDPOINT --suffix-storage-endpoint $SUFFIXES_STORAGE_ENDPOINT --suffix-keyvault-dns $SUFFIXES_KEYVAULT_DNS --endpoint-active-directory-resource-id $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID --endpoint-active-directory $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT --endpoint-active-directory-graph-resource-id $ENDPOINT_GRAPH_ENDPOINT
log_level -i "Set Azure stack environment."
retrycmd_if_failure 5 10 az cloud set -n $ENVIRONMENT_NAME
log_level -i "Update cloud profile with value: $HYBRID_PROFILE."
retrycmd_if_failure 5 10 az cloud update --profile $HYBRID_PROFILE

#####################################################################################
# apimodel gen

log_level -i "Setting general cluster definition properties."

cat $AZURESTACK_CONFIGURATION | \
jq --arg ENDPOINT_PORTAL $ENDPOINT_PORTAL '.properties.customCloudProfile.portalURL = $ENDPOINT_PORTAL'| \
jq --arg REGION_NAME $REGION_NAME '.location = $REGION_NAME' | \
jq --arg MASTER_DNS_PREFIX $MASTER_DNS_PREFIX '.properties.masterProfile.dnsPrefix = $MASTER_DNS_PREFIX' | \
jq '.properties.masterProfile.count'=$MASTER_COUNT | \
jq --arg MASTER_SIZE $MASTER_SIZE '.properties.masterProfile.vmSize=$MASTER_SIZE' | \
jq --arg ADMIN_USERNAME $ADMIN_USERNAME '.properties.linuxProfile.adminUsername = $ADMIN_USERNAME' | \
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' | \
jq --arg AUTHENTICATION_METHOD $AUTHENTICATION_METHOD '.properties.customCloudProfile.authenticationMethod = $AUTHENTICATION_METHOD' | \
jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' | \
jq --arg K8S_VERSION $K8S_AZURE_CLOUDPROVIDER_VERSION '.properties.orchestratorProfile.orchestratorRelease=$K8S_VERSION' | \
jq --arg NETWORK_PLUGIN $NETWORK_PLUGIN '.properties.orchestratorProfile.kubernetesConfig.networkPlugin=$NETWORK_PLUGIN' \
> $AZURESTACK_CONFIGURATION_TEMP

validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL

#####################################################################################
#Linux agent
if [ "$AGENT_COUNT" != "0" ]; then
    log_level -i "Update cluster definition with Linux agent node details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg linuxAgentCount $AGENT_COUNT \
    --arg linuxAgentSize $AGENT_SIZE \
    --arg linuxAvailabilityProfile $AVAILABILITY_PROFILE \
    --arg NODE_DISTRO "ubuntu" \
    '.properties.agentPoolProfiles += [{"name": "linuxpool", "osDiskSizeGB": 100, "AcceleratedNetworkingEnabled": false, "distro": $NODE_DISTRO, "count": $linuxAgentCount | tonumber, "vmSize": $linuxAgentSize, "availabilityProfile": $linuxAvailabilityProfile}]' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Updating cluster definition done with Linux agent node details."
fi

#####################################################################################
#Windows agent
if [ "$WINDOWS_AGENT_COUNT" != "0" ]; then
    log_level -i "Update cluster definition with Windows agent node details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg WINDOWS_ADMIN_USERNAME $WINDOWS_ADMIN_USERNAME '.properties.windowsProfile.adminUsername=$WINDOWS_ADMIN_USERNAME' | \
    jq --arg WINDOWS_ADMIN_PASSWORD $WINDOWS_ADMIN_PASSWORD '.properties.windowsProfile.adminPassword=$WINDOWS_ADMIN_PASSWORD' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg winAgentCount $WINDOWS_AGENT_COUNT --arg winAgentSize $WINDOWS_AGENT_SIZE --arg winAvailabilityProfile $AVAILABILITY_PROFILE\
    '.properties.agentPoolProfiles += [{"name": "windowspool", "osDiskSizeGB": 128, "AcceleratedNetworkingEnabled": false, "osType": "Windows", "count": $winAgentCount | tonumber, "vmSize": $winAgentSize, "availabilityProfile": $winAvailabilityProfile}]' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Updating cluster definition done with Windows agent node details."
fi

log_level -i "Done building cluster definition for windows."
#####################################################################################

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    log_level -i "Setting ADFS specific cluster definition properties."
    ADFS="adfs"
    IDENTITY_SYSTEM_LOWER=$ADFS
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg ADFS $ADFS '.properties.customCloudProfile.identitySystem=$ADFS' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
fi

log_level -i "Done building cluster definition."

if [ $IDENTITY_SYSTEM == "ADFS" ] ; then
    log_level -i "In ADFS section to update (servicePrincipalProfile, authenticationMethod ) configurations."
    export IDENTITY_SYSTEM="adfs"
else
    log_level -i "In AAD section to update (servicePrincipalProfile ) configurations."
    export IDENTITY_SYSTEM="azure_ad"
fi

#####################################################################################

cd $ROOT_PATH/src/github.com/Azure/aks-engine

CLUSTER_DEFN=azurestack.json

export CUSTOM_CLOUD_CLIENT_ID=$SPN_CLIENT_ID
export AUTHENTICATION_METHOD="client_secret"
export CUSTOM_CLOUD_SECRET=$SPN_CLIENT_SECRET
export CLIENT_ID=$SPN_CLIENT_ID
export CLIENT_SECRET=$SPN_CLIENT_SECRET
export TENANT_ID=$TENANT_ID
export SUBSCRIPTION_ID=$TENANT_SUBSCRIPTION_ID
export CLEANUP_ON_EXIT=false
export CLUSTER_DEFINITION=$CLUSTER_DEFN
export LOCATION=$REGION_NAME
export API_PROFILE="2018-03-01-hybrid"
export SERVICE_MANAGEMENT_ENDPOINT=$ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID
export RESOURCE_MANAGER_ENDPOINT=$TENANT_ENDPOINT
export ACTIVE_DIRECTORY_ENDPOINT=$ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT
export GALLERY_ENDPOINT=$ENDPOINT_GALLERY
export GRAPH_ENDPOINT=$ENDPOINT_GRAPH_ENDPOINT
export STORAGE_ENDPOINT_SUFFIX=$SUFFIXES_STORAGE_ENDPOINT
export KEY_VAULT_DNS_SUFFIX=$SUFFIXES_KEYVAULT_DNS
export SERVICE_MANAGEMENT_VM_DNS_SUFFIX="cloudapp.net"
export RESOURCE_MANAGER_VM_DNS_SUFFIX=$FQDN_ENDPOINT_SUFFIX
export SSH_KEY_NAME="id_rsa"
export PORTAL_ENDPOINT=$ENDPOINT_PORTAL
#time sync is a known flake at present w/ 18.04-LTS - should have healthy time synchronization
export GINKGO_SKIP="should be able to produce working LoadBalancers|should have healthy time synchronization"

go env

make bootstrap
make validate-dependencies
make build

if [ -f "./bin/aks-engine" ] ; then
    log_level -i "Found aks-engine binary"
else
    log_level -e "Aks-engine binary not found. Can't run E2E Test"
    exit 1
fi

log_level -i "------------------------------------------------------------------------"
log_level -i "Environment parameter details:"
log_level -i "ACTIVE_DIRECTORY_ENDPOINT : $ACTIVE_DIRECTORY_ENDPOINT"
log_level -i "API_PROFILE: $API_PROFILE"
log_level -i "AUTHENTICATION_METHOD: $AUTHENTICATION_METHOD"
log_level -i "CLEANUP_ON_EXIT: $CLEANUP_ON_EXIT"
log_level -i "CLIENT_ID: $CLIENT_ID"
log_level -i "CLIENT_SECRET :$CLIENT_SECRET"
log_level -i "CLUSTER_DEFINITION $CLUSTER_DEFINITION"
log_level -i "CUSTOM_CLOUD_CLIENT_ID: $CUSTOM_CLOUD_CLIENT_ID"
log_level -i "CUSTOM_CLOUD_SECRET: $CUSTOM_CLOUD_SECRET"
log_level -i "GALLERY_ENDPOINT: $GALLERY_ENDPOINT"
log_level -i "GRAPH_ENDPOINT: $GRAPH_ENDPOINT"
log_level -i "KEY_VAULT_DNS_SUFFIX: $KEY_VAULT_DNS_SUFFIX"
log_level -i "IDENTITY_SYSTEM: $IDENTITY_SYSTEM"
log_level -i "LOCATION: $LOCATION"
log_level -i "PORTAL_ENDPOINT: $ENDPOINT_PORTAL"
log_level -i "REGION_NAME: $REGION_NAME"
log_level -i "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
log_level -i "RESOURCE_MANAGER_ENDPOINT : $RESOURCE_MANAGER_ENDPOINT"
log_level -i "RESOURCE_MANAGER_VM_DNS_SUFFIX: $RESOURCE_MANAGER_VM_DNS_SUFFIX"
log_level -i "SERVICE_MANAGEMENT_ENDPOINT: $SERVICE_MANAGEMENT_ENDPOINT"
log_level -i "SERVICE_MANAGEMENT_VM_DNS_SUFFIX: $SERVICE_MANAGEMENT_VM_DNS_SUFFIX"
log_level -i "SSH_KEY_NAME: $SSH_KEY_NAME"
log_level -i "STORAGE_ENDPOINT_SUFFIX: $STORAGE_ENDPOINT_SUFFIX"
log_level -i "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
log_level -i "TENANT_ID: $TENANT_ID"
log_level -i "------------------------------------------------------------------------"

make test-kubernetes &> deploy_test_results

RESULT=$?

chown -R azureuser /home/azureuser
chmod -R u=rwx /home/azureuser

# Below condition is to make the deployment success even if the test cases fail, 
# if the deployment of kubernetes fails it exits with the failure code
log_level -i "Result: $RESULT"
if [ $RESULT -gt 3 ] ; then
    exit 1
else
    exit 0
fi
