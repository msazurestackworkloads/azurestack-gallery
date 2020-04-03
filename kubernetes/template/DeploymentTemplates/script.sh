#!/bin/bash -e

ERR_APT_INSTALL_TIMEOUT=9 # Timeout installing required apt packages
ERR_AKSE_DOWNLOAD=10 # Failure downloading AKS-Engine binaries
ERR_AKSE_DEPLOY=12 # Failure calling AKS-Engine's deploy operation
ERR_TEMPLATE_GENERATION=13 # Failure downloading AKS-Engine template
ERR_INVALID_AGENT_COUNT_VALUE=14 # Both Windows and Linux agent value is zero
ERR_CACERT_INSTALL=20 # Failure moving CA certificate
ERR_METADATA_ENDPOINT=30 # Failure calling the metadata endpoint
ERR_API_MODEL=40 # Failure building API model using user input
ERR_AZS_CLOUD_REGISTER=50 # Failure calling az cloud register
ERR_APT_UPDATE_TIMEOUT=99 # Timeout waiting for apt-get update to complete
#ERR_AKSE_GENERATE=11 # Failure calling AKS-Engine's generate operation
#ERR_MS_GPG_KEY_DOWNLOAD_TIMEOUT=26 # Timeout waiting for Microsoft's GPG key download
#ERR_AZS_CLOUD_ENVIRONMENT=51 # Failure setting az cloud environment
#ERR_AZS_CLOUD_PROFILE=52 # Failure setting az cloud profile
#ERR_AZS_LOGIN_AAD=53 # Failure to log in to AAD environment
#ERR_AZS_LOGIN_ADFS=54 # Failure to log in to ADFS environment
#ERR_AZS_ACCOUNT_SUB=55 # Failure setting account default subscription

function collect_deployment_and_operations
{
    # Store main exit code
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ]; then
        log_level -i "CustomScript extension failed with exit code $EXIT_CODE"
    fi
    
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
}

# Download msazurestackworkloads' AKSe fork and move relevant files to the working directory
download_akse()
{
    if [ ! $DISCONNECTED_AKS_ENGINE_URL ]
    then
        AKSE_ZIP_NAME="aks-engine-$AKSE_RELEASE_VERSION-linux-amd64"
        AKSE_ZIP_URL="$AKSE_BASE_URL/$AKSE_RELEASE_VERSION/$AKSE_ZIP_NAME.tar.gz"
    else
        AKSE_ZIP_URL=$DISCONNECTED_AKS_ENGINE_URL
    fi
    log_level -i "AKSE_ZIP_URL:$AKSE_ZIP_URL"

    curl --retry 5 --retry-delay 10 --max-time 60 -L -s -f -O $AKSE_ZIP_URL || exit $ERR_AKSE_DOWNLOAD

    mkdir -p ./bin
    AKSE_LOCAL_ZIP_NAME=${AKSE_ZIP_URL##*/}
    tar -xf $AKSE_LOCAL_ZIP_NAME
    AKSE_LOCAL_FILENAME=`basename -s .tar.gz $AKSE_LOCAL_ZIP_NAME`
    cp ./$AKSE_LOCAL_FILENAME/aks-engine ./bin

    
    AKSE_LOCATION=./bin/aks-engine
    if [ ! -f $AKSE_LOCATION ]; then
        log_level -e "aks-engine binary not found in expected location"
        log_level -e "Expected location: $AKSE_LOCATION"
        exit 1
    fi
    
    generate_api_model || exit $ERR_TEMPLATE_GENERATION

    
    DEFINITION_TEMPLATE="./$DEFINITION_TEMPLATE_NAME"
    if [ ! -f $DEFINITION_TEMPLATE ]; then
        log_level -e "API model template for Kubernetes not found in expected location"
        log_level -e "Expected location: $DEFINITION_TEMPLATE"
        exit 1
    fi
    
    if [ ! -s $DEFINITION_TEMPLATE ]; then
        log_level -e "Downloaded API model template for Kubernetes is an empty file."
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

generate_api_model()
{
    touch $DEFINITION_TEMPLATE_NAME
    cat > $DEFINITION_TEMPLATE_NAME <<EOL
{
    "apiVersion": "vlabs",
    "location": "",
    "properties": {
        "orchestratorProfile": {
            "orchestratorType": "Kubernetes",
            "orchestratorRelease": ""
            "kubernetesConfig": {
                "useInstanceMetadata": false,
                "networkPlugin": "",
                "containerRuntime": "",
                "kubeletConfig": {
                    "--node-status-update-frequency": "1m"
                },
                "controllerManagerConfig": {
                    "--node-monitor-grace-period": "5m",
                    "--pod-eviction-timeout": "5m",
                    "--route-reconciliation-period": "1m"
                },
                "addons": []
            }
        },
        "customCloudProfile": {
            "portalURL": ""
        },
        "masterProfile": {
            "dnsPrefix": "",
            "distro": "",
            "osDiskSizeGB": 200,
            "availabilityProfile": "",
            "count": 3,
            "vmSize": ""
        },
        "agentPoolProfiles": [],
        "linuxProfile": {
            "adminUsername": "",
            "ssh": {
                "publicKeys": [
                    {
                        "keyData": ""
                    }
                ]
            }
        },
        "windowsProfile": {
            "adminUsername": "",
            "adminPassword": "",
            "sshEnabled": true
        },
        "servicePrincipalProfile": {
            "clientId": "",
            "secret": ""
        }
    }
}
EOL

}

#####################################################################################
# start

log_level -i "Starting Kubernetes cluster deployment: v1.0.3"
log_level -i "Running script as:  $(whoami)"
log_level -i "System information: $(uname -a)"

log_level -i "------------------------------------------------------------------------"
log_level -i "ARM parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "ADMIN_USERNAME:                           $ADMIN_USERNAME"
log_level -i "AGENT_COUNT:                              $AGENT_COUNT"
log_level -i "AGENT_SIZE:                               $AGENT_SIZE"
log_level -i "AGENT_SUBNET_NAME:                        $AGENT_SUBNET_NAME"
log_level -i "AKSE_BASE_URL                             $AKSE_BASE_URL"
log_level -i "AKSE_RELEASE_VERSION                      $AKSE_RELEASE_VERSION"
log_level -i "AVAILABILITY_PROFILE                      $AVAILABILITY_PROFILE"
log_level -i "CUSTOM_VNET_NAME:                         $CUSTOM_VNET_NAME"
log_level -i "DEFINITION_TEMPLATE_NAME:                 $DEFINITION_TEMPLATE_NAME"
log_level -i "DISCONNECTED_AKS_ENGINE_URL:              $DISCONNECTED_AKS_ENGINE_URL"
log_level -i "ENABLE_TILLER:                            $ENABLE_TILLER"
log_level -i "CONTAINER_RUNTIME:                        $CONTAINER_RUNTIME"
log_level -i "FIRST_CONSECUTIVE_STATIC_IP:              $FIRST_CONSECUTIVE_STATIC_IP"
log_level -i "GALLERY_BRANCH:                           $GALLERY_BRANCH"
log_level -i "GALLERY_REPO:                             $GALLERY_REPO"
log_level -i "IDENTITY_SYSTEM:                          $IDENTITY_SYSTEM"
log_level -i "K8S_AZURE_CLOUDPROVIDER_VERSION:          $K8S_AZURE_CLOUDPROVIDER_VERSION"
log_level -i "MASTER_COUNT:                             $MASTER_COUNT"
log_level -i "MASTER_DNS_PREFIX:                        $MASTER_DNS_PREFIX"
log_level -i "MASTER_SIZE:                              $MASTER_SIZE"
log_level -i "MASTER_SUBNET_NAME:                       $MASTER_SUBNET_NAME"
log_level -i "NETWORK_PLUGIN:                           $NETWORK_PLUGIN"
log_level -i "NETWORK_POLICY:                           $NETWORK_POLICY"
log_level -i "NODE_DISTRO:                              $NODE_DISTRO"
log_level -i "PUBLICIP_DNS:                             $PUBLICIP_DNS"
log_level -i "PUBLICIP_FQDN:                            $PUBLICIP_FQDN"
log_level -i "REGION_NAME:                              $REGION_NAME"
log_level -i "RESOURCE_GROUP_NAME:                      $RESOURCE_GROUP_NAME"
log_level -i "SPN_CLIENT_ID:                            ----"
log_level -i "SPN_CLIENT_SECRET:                        ----"
log_level -i "SSH_PUBLICKEY:                            ----"
log_level -i "STORAGE_PROFILE:                          $STORAGE_PROFILE"
log_level -i "TENANT_ID:                                $TENANT_ID"
log_level -i "TENANT_SUBSCRIPTION_ID:                   $TENANT_SUBSCRIPTION_ID"
log_level -i "WINDOWS_ADMIN_USERNAME:                   $WINDOWS_ADMIN_USERNAME"
log_level -i "WINDOWS_ADMIN_PASSWORD:                   ----"
log_level -i "WINDOWS_AGENT_COUNT:                      $WINDOWS_AGENT_COUNT"
log_level -i "WINDOWS_AGENT_SIZE:                       $WINDOWS_AGENT_SIZE"
log_level -i "WINDOWS_CUSTOM_PACKAGE:                   $WINDOWS_CUSTOM_PACKAGE"


if [[ "$WINDOWS_AGENT_COUNT" == "0" ]] && [[ "$AGENT_COUNT" == "0" ]]; then
    exit $ERR_INVALID_AGENT_COUNT_VALUE
fi

log_level -i "------------------------------------------------------------------------"
log_level -i "Constants"
log_level -i "------------------------------------------------------------------------"

ENVIRONMENT_NAME=AzureStackCloud
AUTH_METHOD="client_secret"
IDENTITY_SYSTEM_LOWER="azure_ad"

log_level -i "ENVIRONMENT_NAME: $ENVIRONMENT_NAME"

log_level -i "------------------------------------------------------------------------"
log_level -i "Inner variables"
log_level -i "------------------------------------------------------------------------"

EXTERNAL_FQDN="${PUBLICIP_FQDN//$PUBLICIP_DNS.$REGION_NAME.cloudapp.}"
TENANT_ENDPOINT="https://management.$REGION_NAME.$EXTERNAL_FQDN"
AZURESTACK_RESOURCE_METADATA_ENDPOINT="$TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01"

log_level -i "AZURESTACK_RESOURCE_METADATA_ENDPOINT:    $AZURESTACK_RESOURCE_METADATA_ENDPOINT"
log_level -i "ENVIRONMENT_NAME:                         $ENVIRONMENT_NAME"
log_level -i "EXTERNAL_FQDN:                            $EXTERNAL_FQDN"
log_level -i "STORAGE_PROFILE:                          $STORAGE_PROFILE"
log_level -i "TENANT_ENDPOINT:                          $TENANT_ENDPOINT"

log_level -i "------------------------------------------------------------------------"

WAIT_TIME_SECONDS=20
log_level -i "Waiting for $WAIT_TIME_SECONDS seconds to allow the system to stabilize.";
sleep $WAIT_TIME_SECONDS

#####################################################################################
# apt packages
# leaving this part connected until the modules are added to vhd

if [ ! $DISCONNECTED_AKS_ENGINE_URL ]
then
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
    || exit $ERR_APT_INSTALL_TIMEOUT
fi

#####################################################################################
# certificates

log_level -i "Moving certificates to the expected locations as required by AKSe"
ensure_certificates || exit $ERR_CACERT_INSTALL


#####################################################################################
# aks-engine

log_level -i "Downloading AKS-Engine binary and cluster definition templates"

mkdir -p $PWD/bin

AZURESTACK_CONFIGURATION=$PWD/bin/azurestack.json
AZURESTACK_CONFIGURATION_TEMP=$PWD/bin/azurestack.tmp

download_akse || exit $ERR_AKSE_DOWNLOAD

#####################################################################################
# apimodel values

log_level -i "Computing cluster definition values."

METADATA=`curl -s -f --retry 10 $AZURESTACK_RESOURCE_METADATA_ENDPOINT` || exit $ERR_METADATA_ENDPOINT
echo $METADATA > metadata.json

ENDPOINT_PORTAL=`echo $METADATA | jq '.portalEndpoint' | xargs`

log_level -i "ENDPOINT_PORTAL: $ENDPOINT_PORTAL"

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    log_level -i "Setting ADFS specific cluster definition properties."
    IDENTITY_SYSTEM_LOWER="adfs"
    
    # Trim "adfs" suffix
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA | jq '.authentication.loginEndpoint' | xargs | sed -e 's/adfs*$//' | xargs`
else
    ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA | jq '.authentication.loginEndpoint' | xargs`
fi

log_level -i "ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"

#####################################################################################
#Linux agent
if [ "$AGENT_COUNT" != "0" ]; then
    log_level -i "Update cluster definition with Linux agent node details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg linuxAgentCount $AGENT_COUNT \
    --arg linuxAgentSize $AGENT_SIZE \
    --arg linuxAvailabilityProfile $AVAILABILITY_PROFILE \
    --arg NODE_DISTRO $NODE_DISTRO \
    '.properties.agentPoolProfiles += [{"name": "linuxpool", "osDiskSizeGB": 200, "AcceleratedNetworkingEnabled": false, "distro": $NODE_DISTRO, "count": $linuxAgentCount | tonumber, "vmSize": $linuxAgentSize, "availabilityProfile": $linuxAvailabilityProfile}]' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Updating cluster definition done with Linux agent node details."
fi

#####################################################################################
#Windows Agent
if [ "$WINDOWS_AGENT_COUNT" != "0" ]; then
    log_level -i "Update cluster definition with Windows profile details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg WINDOWS_ADMIN_USERNAME $WINDOWS_ADMIN_USERNAME '.properties.windowsProfile.adminUsername=$WINDOWS_ADMIN_USERNAME' | \
    jq --arg WINDOWS_ADMIN_PASSWORD $WINDOWS_ADMIN_PASSWORD '.properties.windowsProfile.adminPassword=$WINDOWS_ADMIN_PASSWORD' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Update Windows agent node details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg winAgentCount $WINDOWS_AGENT_COUNT --arg winAgentSize $WINDOWS_AGENT_SIZE --arg winAvailabilityProfile $AVAILABILITY_PROFILE \
    '.properties.agentPoolProfiles += [{"name": "windowspool", "osDiskSizeGB": 128, "AcceleratedNetworkingEnabled": false, "osType": "Windows", "count": $winAgentCount | tonumber, "vmSize": $winAgentSize, "availabilityProfile": $winAvailabilityProfile}]' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Updating cluster definition done with Windows agent node details."
fi

#####################################################################################
# custom windows package URL
if [ "$WINDOWS_CUSTOM_PACKAGE" != "" ]; then
    log_level -i "Adding Windows custom package URL details."
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg CUSTOM_PACKAGE $WINDOWS_CUSTOM_PACKAGE '.properties.orchestratorProfile.kubernetesConfig += {"customWindowsPackageURL": $CUSTOM_PACKAGE } '  \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    log_level -i "Done updating Windows custom package URL details."
fi

#####################################################################################
#custom vnet config
if [ "$CUSTOM_VNET_NAME" != "" ]; then
    log_level -i "Setting general custom vnet properties."
    MASTER_VNET_ID="/subscriptions/$TENANT_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$CUSTOM_VNET_NAME/subnets/$MASTER_SUBNET_NAME"
    AGENT_VNET_ID="/subscriptions/$TENANT_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$CUSTOM_VNET_NAME/subnets/$AGENT_SUBNET_NAME"
    
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg MASTER_VNET_ID $MASTER_VNET_ID  '.properties.masterProfile += {"vnetSubnetId": $MASTER_VNET_ID } '| \
    jq --arg FIRST_CONSECUTIVE_STATIC_IP $FIRST_CONSECUTIVE_STATIC_IP  '.properties.masterProfile += {"firstConsecutiveStaticIP": $FIRST_CONSECUTIVE_STATIC_IP } ' | \
    jq --arg AGENT_VNET_ID $AGENT_VNET_ID '.properties.agentPoolProfiles[0] += {"vnetSubnetId": $AGENT_VNET_ID } '  \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
    
    if [ "$WINDOWS_AGENT_COUNT" != "0" ]; then
        
        log_level -i "Updating custom vnet properties for Windows nodes."
        if [ "$AGENT_COUNT" != "0" ]; then
            cat $AZURESTACK_CONFIGURATION | \
            jq --arg AGENT_VNET_ID $AGENT_VNET_ID '.properties.agentPoolProfiles[1] += {"vnetSubnetId": $AGENT_VNET_ID } '  \
            > $AZURESTACK_CONFIGURATION_TEMP
        else
            cat $AZURESTACK_CONFIGURATION | \
            jq --arg AGENT_VNET_ID $AGENT_VNET_ID '.properties.agentPoolProfiles[0] += {"vnetSubnetId": $AGENT_VNET_ID } '  \
            > $AZURESTACK_CONFIGURATION_TEMP
        fi
        
        validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
        log_level -i "Custom vnet properties update for Windows nodes done ."
    fi
    
    log_level -i "Done building custom vnet  definition."
fi

#####################################################################################
#custom network policy config
if [ "$NETWORK_POLICY" != "" ]; then
    log_level -i "Setting network policy property."
    cat $AZURESTACK_CONFIGURATION | jq --arg NETWORK_POLICY $NETWORK_POLICY '.properties.orchestratorProfile.kubernetesConfig.networkPolicy=$NETWORK_POLICY' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    log_level -i "Done setting network policy property."
fi

#####################################################################################
#tiller

if [ "$ENABLE_TILLER" == "true" ]; then
    log_level -i "Enabling Tiller Addon"
    cat $AZURESTACK_CONFIGURATION | \
    jq --arg enableTiller $ENABLE_TILLER \
    '.properties.orchestratorProfile.kubernetesConfig.addons += [{"name": "tiller", "enabled": true}]' \
    > $AZURESTACK_CONFIGURATION_TEMP
    
    validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL
fi

#####################################################################################
# apimodel gen

log_level -i "Setting general cluster definition properties."

cat $AZURESTACK_CONFIGURATION | \
jq --arg ENDPOINT_PORTAL $ENDPOINT_PORTAL '.properties.customCloudProfile.portalURL = $ENDPOINT_PORTAL'| \
jq --arg REGION_NAME $REGION_NAME '.location = $REGION_NAME' | \
jq --arg MASTER_DNS_PREFIX $MASTER_DNS_PREFIX '.properties.masterProfile.dnsPrefix = $MASTER_DNS_PREFIX' | \
jq --arg NODE_DISTRO $NODE_DISTRO '.properties.masterProfile.distro = $NODE_DISTRO' | \
jq '.properties.masterProfile.count'=$MASTER_COUNT | \
jq --arg MASTER_SIZE $MASTER_SIZE '.properties.masterProfile.vmSize=$MASTER_SIZE' | \
jq --arg ADMIN_USERNAME $ADMIN_USERNAME '.properties.linuxProfile.adminUsername = $ADMIN_USERNAME' | \
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' | \
jq --arg AUTH_METHOD $AUTH_METHOD '.properties.customCloudProfile.authenticationMethod=$AUTH_METHOD' | \
jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' | \
jq --arg IDENTITY_SYSTEM_LOWER $IDENTITY_SYSTEM_LOWER '.properties.customCloudProfile.identitySystem=$IDENTITY_SYSTEM_LOWER' | \
jq --arg K8S_VERSION $K8S_AZURE_CLOUDPROVIDER_VERSION '.properties.orchestratorProfile.orchestratorRelease=$K8S_VERSION' | \
jq --arg NETWORK_PLUGIN $NETWORK_PLUGIN '.properties.orchestratorProfile.kubernetesConfig.networkPlugin=$NETWORK_PLUGIN' | \
jq --arg CONTAINER_RUNTIME $CONTAINER_RUNTIME '.properties.orchestratorProfile.kubernetesConfig.containerRuntime=$CONTAINER_RUNTIME' \
> $AZURESTACK_CONFIGURATION_TEMP

validate_and_restore_cluster_definition $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION || exit $ERR_API_MODEL


log_level -i "Done building cluster definition."

#####################################################################################
# aks-engine commands

log_level -i "Deploying using AKS Engine."

./bin/aks-engine deploy \
-g $RESOURCE_GROUP_NAME \
--api-model $AZURESTACK_CONFIGURATION \
--auth-method $AUTH_METHOD \
--azure-env $ENVIRONMENT_NAME \
--location $REGION_NAME \
--client-id $SPN_CLIENT_ID \
--client-secret $SPN_CLIENT_SECRET \
--identity-system $IDENTITY_SYSTEM_LOWER \
--subscription-id $TENANT_SUBSCRIPTION_ID || exit $ERR_AKSE_DEPLOY

log_level -i "Kubernetes cluster deployment complete."
