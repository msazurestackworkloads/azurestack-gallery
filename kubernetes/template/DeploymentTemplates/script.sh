set -e

### 
#	<summary>
#   	Logs output by prepending date and log output type(Error, warning, info or verbose).
#   </summary>
#	<param name="1">Type to log. (Valid values are: -e, -w, -i)</param>
#	<param name="...">Output echo string.</param>
#	<returns>None</returns>
#	<exception>None</exception>
#	<remarks>Called within same scripts.</remarks>
###
log_output() 
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
#	<summary>
#   	Retry given command given number of times in case we have hit any failure.
#   </summary>
#	<param name="1">Number of retry.</param>
#	<param name="2">Wait time between retry.</param>
#	<param name="...">Command to be executed.</param>
#	<returns>None</returns>
#	<exception>None</exception>
#	<remarks>Called within same scripts.</remarks>
###
retrycmd_if_failure() 
{ 
	retries=$1; 
	wait=$2; 
	for i in $(seq 1 $retries); do 
		${@:3}; [ $? -eq 0  ] && break || sleep $wait; 
	done; 
	log_output -i "Command Executed $i times."; 
}

### 
#	<summary>
#   	Validate if file exist and it has non zero bytes. If validation passes moves file to new location.
#   </summary>
#	<param name="1">Source File Name.</param>
#	<param name="2">Destination File Name.</param>
#	<returns>None</returns>
#	<exception>Can exit with error code 1 in case file does not exist or size is zero.</exception>
#	<remarks>Called within same scripts.</remarks>
###
check_and_move_azurestack_configuration() {

	if [ -s $1 ] ; then
		log_output -i "Found '$1' in path '$PWD' and is greater than zero bytes."
	else
		log_output -e "File '$1' does not exist in '$PWD' or is zero length. Error happend during building input API model or cluster definition."
		exit 1
	fi
	
	log_output -i "Moving file '$1' to '$2'"
	sudo mv $1 $2
	log_output -i "Completed creating API model file with given stamp information."
}

### 
#	<summary>
#   	Create cert and key from a given secret.
#   </summary>
#	<param name="1">Service principle secret.</param>
#	<param name="2">Certificate PFX file name.</param>
#	<param name="3">Certificate PEM file name.</param>
#	<returns>None</returns>
#	<exception>None</exception>
#	<remarks>Called within same scripts.</remarks>
###
convert_to_cert() {

    log_output -i "Decoding secret to json."
    echo $1 | base64 --decode > cert.json
	
	log_output -i "Saving data value to $2."	
    cat cert.json | jq '.data' | tr -d \" | base64 --decode > $2
	
	log_output -i "Extracting the password."
    PASSWORD=$(cat cert.json | jq '.password' | tr -d \")

	log_output -i "Converting data into pem format."
	openssl pkcs12 -in $2 -nodes -passin pass:$PASSWORD -out $3
}

### 
#	<summary>
#   	Copying AzureStack root certificate to appropriate store.
#   </summary>
#	<returns>None</returns>
#	<exception>None</exception>
#	<remarks>Called within same scripts.</remarks>
###
ensureCertificates()
{
    log_output -i "Updating certificates to appropriate store"

    AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
    AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"
	
	log_output -i "Copy cert from '$AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH' to '$AZURESTACK_ROOT_CERTIFICATE_DEST_PATH' "
	sudo cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH
	
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`	
    AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`

    log_output -i "AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT"
    log_output -i "AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT"

    update-ca-certificates

	# Azure CLI specific changes.
	export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    sudo sed -i -e "\$aREQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" /etc/environment
	
    AZURESTACK_RESOURCE_METADATA_ENDPOINT="$TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01"
    curl $AZURESTACK_RESOURCE_METADATA_ENDPOINT
}

# Basic details of the system
log_output -i "Starting Kubernetes cluster deployment."
log_output -i "Running  script as : $(whoami)"

log_output -i "System information: $(sudo uname -a)"
WAIT_TIME_SECONDS=20
log_output -i "Waiting for $WAIT_TIME_SECONDS seconds for system to get into stabe state."
sleep $WAIT_TIME_SECONDS

# Script parameters
log_output -i "------------------------------------------------------------------------"
log_output -i "Input parameter details:"
log_output -i "ADMIN_USERNAME: $ADMIN_USERNAME"
log_output -i "AGENT_COUNT: $AGENT_COUNT"
log_output -i "AGENT_SIZE: $AGENT_SIZE"
log_output -i "IDENTITY_SYSTEM: $IDENTITY_SYSTEM" 
log_output -i "K8S_AZURE_CLOUDPROVIDER_VERSION: $K8S_AZURE_CLOUDPROVIDER_VERSION"
log_output -i "MASTER_COUNT: $MASTER_COUNT"
log_output -i "MASTER_DNS_PREFIX: $MASTER_DNS_PREFIX"
log_output -i "MASTER_SIZE: $MASTER_SIZE"
log_output -i "PUBLICIP_DNS: $PUBLICIP_DNS"
log_output -i "PUBLICIP_FQDN: $PUBLICIP_FQDN"
log_output -i "REGION_NAME: $REGION_NAME"
log_output -i "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
log_output -i "SSH_PUBLICKEY: $SSH_PUBLICKEY"
log_output -i "STORAGE_PROFILE: $STORAGE_PROFILE"
log_output -i "TENANT_ID: $TENANT_ID"
log_output -i "TENANT_SUBSCRIPTION_ID: $TENANT_SUBSCRIPTION_ID"
log_output -i "------------------------------------------------------------------------"

#####################################################################################
# Install all prequisite. 
log_output -i "Update the system to latest."
retrycmd_if_failure 5 10 sudo apt-get update -y

log_output -i "Installing pax for string manipulation."
retrycmd_if_failure 5 10 sudo apt-get install pax -y

log_output -i "Installing jq for JSON manipulation."
retrycmd_if_failure 5 10 sudo apt-get install jq -y

log_output -i "Installing curl."
retrycmd_if_failure 5 10 sudo apt-get install curl -y

log_output -i "Installing apt-transport-https and lsb-release required for Azure CLI."
retrycmd_if_failure 5 10 sudo apt-get install apt-transport-https lsb-release -y

log_output -i "Installing software-properties-common and dirmngr required for Azure CLI."
retrycmd_if_failure 5 10 sudo apt-get install software-properties-common dirmngr -y

log_output -i "Update system again to latest."
retrycmd_if_failure 5 10 sudo apt-get update -y

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
log_output -i "Get the Microsoft signing key."
retrycmd_if_failure 5 10 sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv --keyserver packages.microsoft.com --recv-keys $RECV_KEY

log_output -i "Update system again to latest."
retrycmd_if_failure 5 10 sudo apt-get update 

log_output -i "Installing azure cli...."
retrycmd_if_failure 5 10 sudo apt-get install azure-cli

log_output -i "Azure CLI version : $(az --version)"

#####################################################################################
#Section to install/get AKS-Engine binary.
log_output -i "Getting AKS-Engine binary."

# Todo update release branch details: msazurestackworkloads, azsmaster
retrycmd_if_failure 5 10 git clone https://github.com/msazurestackworkloads/aks-engine -b azsmaster
cd aks-engine

log_output -i "We are going to use an existing AKS-Engine binary."
log_output -i "Extract zip file."
sudo mkdir bin
sudo tar -zxvf examples/azurestack/aks-engine.tgz
sudo mv aks-engine bin/

log_output -i "Checking if aks-engine binary is available."
if [ -f "./bin/aks-engine" ] ; then
	log_output -i "Found aks-engine.exe"
else
	log_output -e "Missing aks-engine.exe. Exiting!"
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

log_output -i "EXTERNAL_FQDN is:$EXTERNAL_FQDN"
log_output -i "TENANT_ENDPOINT is:$TENANT_ENDPOINT"

retrycmd_if_failure 20 30 ensureCertificates

#####################################################################################
# Section to create API model file for AKS-Engine.

# First check if API model file exist else exit.
log_output -i "Overriding default file with correct values in API model or cluster definition."
if [ -f "examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json" ] ; then
	log_output -i "Found file: azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json."
else
	log_output -i "File azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json does not exist. Exiting..."
	exit 1
fi

# Check if API model file has some data or not else exit.
AZURESTACK_CONFIGURATION_TEMP="${AZURESTACK_CONFIGURATION_TEMP:-azurestack_temp.json}"
AZURESTACK_CONFIGURATION="${AZURESTACK_CONFIGURATION:-azurestack.json}"
log_output -i "Copying default API model file to $PWD."
sudo cp examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json $AZURESTACK_CONFIGURATION
if [ -s "$AZURESTACK_CONFIGURATION" ] ; then
	log_output -i "Found $AZURESTACK_CONFIGURATION in $PWD and is greater than zero bytes"
else
	log_output -i "File $AZURESTACK_CONFIGURATION does not exist in $PWD or is zero length."
	exit 1
fi

METADATA=`curl --retry 10 $TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01`
ENDPOINT_GRAPH_ENDPOINT=`echo $METADATA  | jq '.graphEndpoint' | tr -d \"`
ENDPOINT_GALLERY=`echo $METADATA  | jq '.galleryEndpoint' | tr -d \"`
ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=`echo $METADATA  | jq '.authentication.audiences'[0] | tr -d \"`
log_output -i "Endpoint active directory resource id is: $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID."

if [ $IDENTITY_SYSTEM == "ADFS" ] ; then
	# Trim "adfs" from end of login endpoint if it is ADFS
	log_output -i "In ADFS section to get(Active_Directory_Endpoint, SPN_CLIENT_SECRET) configurations."
	ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA  | jq '.authentication.loginEndpoint' | tr -d \" | sed -e 's/adfs*$//' | tr -d \" `
	log_output -i "Active directory endpoint is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"
	
	# Parse SPN_CLIENT_SECRET to get pfx and password and generate pem using PFX
	log_output -i "Parsing secret to get pem and pfx for ADFS scenario."
	CERTIFICATE_PFX_LOCATION="spnauth.pfx"
	CERTIFICATE_PEM_LOCATION="spnauth.pem"
	convert_to_cert $SPN_CLIENT_SECRET $CERTIFICATE_PFX_LOCATION $CERTIFICATE_PEM_LOCATION
	log_output -i "Able to get PFX value in : '$CERTIFICATE_PFX_LOCATION'  and pem value in '$CERTIFICATE_PEM_LOCATION'."
	
else
	log_output -i "In AAD section to get(Active_Directory_Endpoint) configurations.."
	ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA  | jq '.authentication.loginEndpoint' | tr -d \"`
	log_output -i "Active directory endpoint is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT"
fi

# Start updating file with passed values.
STORAGE_PROFILE="${STORAGE_PROFILE:-blobdisk}"
# use blobdisk and AvailabilitySet
if [ "$STORAGE_PROFILE" == "blobdisk" ] ; then

	log_output -i "Updating the API model file to include blob disk values."
	sudo cat $AZURESTACK_CONFIGURATION | jq --arg AvailabilitySet "AvailabilitySet" '.properties.agentPoolProfiles[0].availabilityProfile=$AvailabilitySet' | \
	jq --arg StorageAccount "StorageAccount" '.properties.agentPoolProfiles[0].storageProfile=$StorageAccount' | \
	jq --arg StorageAccount "StorageAccount" '.properties.masterProfile.storageProfile=$StorageAccount' > $AZURESTACK_CONFIGURATION_TEMP

	log_output -i "Checking and moving 'use blobdisk and AvailabilitySet' info from temp file to main api model file."
	check_and_move_azurestack_configuration $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION
fi

sudo cat $AZURESTACK_CONFIGURATION | jq --arg ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID '.properties.customCloudProfile.environment.serviceManagementEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID'|\
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
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' >  $AZURESTACK_CONFIGURATION_TEMP

log_output -i "Checking and moving temp file data to main api model file."
check_and_move_azurestack_configuration $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION

if [ $IDENTITY_SYSTEM == "ADFS" ] ; then
	log_output -i "In ADFS section to update (servicePrincipalProfile, authenticationMethod ) configurations."
	IDENTITY_SYSTEM_LOWER=`echo "$IDENTITY_SYSTEM" | tr '[:upper:]' '[:lower:]'`
	sudo cat $AZURESTACK_CONFIGURATION | jq --arg IDENTITY_SYSTEM_LOWER $IDENTITY_SYSTEM_LOWER '.properties.customCloudProfile.identitySystem=$IDENTITY_SYSTEM_LOWER' | \
	jq --arg authenticationMethod "client_certificate" '.properties.customCloudProfile.authenticationMethod=$authenticationMethod' | \
	jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
	jq --arg SPN_CLIENT_SECRET_KEYVAULT_ID $SPN_CLIENT_SECRET_KEYVAULT_ID '.properties.servicePrincipalProfile.keyvaultSecretRef.vaultID = $SPN_CLIENT_SECRET_KEYVAULT_ID' | \
	jq --arg SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME $SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME '.properties.servicePrincipalProfile.keyvaultSecretRef.secretName = $SPN_CLIENT_SECRET_KEYVAULT_SECRET_NAME' >  $AZURESTACK_CONFIGURATION_TEMP
	
	log_output -i "Append adfs back to Active directory endpoint as it is required in Azure CLI to register and login."
	ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=${ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT}adfs
	log_output -i "Final ACTIVE_DIRECTORY endpoint value for adfs is: $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT."
else
	log_output -i "In AAD section to update (servicePrincipalProfile ) configurations."
	sudo cat $AZURESTACK_CONFIGURATION | jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
	jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' >  $AZURESTACK_CONFIGURATION_TEMP
fi

log_output -i "Checking and moving temp file data(servicePrincipalProfile) to main api model file."
check_and_move_azurestack_configuration $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION

log_output -i "Completed building API model file based on passed stamp information and other parameters."

#####################################################################################
# Section to gernate Arm template using AKS Engine, login using Azure CLI and deploy the template.
# https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-version-profiles-azurecli2#connect-to-azure-stack
HYBRID_PROFILE=2018-03-01-hybrid
log_output -i "Register to AzureStack cloud using below command."
retrycmd_if_failure 5 10 az cloud register -n $ENVIRONMENT_NAME --endpoint-resource-manager $TENANT_ENDPOINT --suffix-storage-endpoint $SUFFIXES_STORAGE_ENDPOINT --suffix-keyvault-dns $SUFFIXES_KEYVAULT_DNS --endpoint-active-directory-resource-id $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID --endpoint-active-directory $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT --endpoint-active-directory-graph-resource-id $ENDPOINT_GRAPH_ENDPOINT
log_output -i "Set Azure stack environment."
retrycmd_if_failure 5 10 az cloud set -n $ENVIRONMENT_NAME
log_output -i "Update cloud profile with value: $HYBRID_PROFILE."
retrycmd_if_failure 5 10 az cloud update --profile $HYBRID_PROFILE

if [ $IDENTITY_SYSTEM == "ADFS" ] ; then
	log_output -i "Login to ADFS environment using Azure CLI."
	retrycmd_if_failure 5 10 az login --service-principal -u $SPN_CLIENT_ID  -p $PWD/$CERTIFICATE_PEM_LOCATION --tenant $TENANT_ID
else
	log_output -i "Login to AAD environment using Azure CLI."
	retrycmd_if_failure 5 10 az login --service-principal -u $SPN_CLIENT_ID -p $SPN_CLIENT_SECRET --tenant $TENANT_ID
fi

log_output -i "Setting subscription to $TENANT_SUBSCRIPTION_ID"
retrycmd_if_failure 5 10 az account set --subscription $TENANT_SUBSCRIPTION_ID > /dev/null

log_output -i "Generate ARM template using AKS-Engine."
retrycmd_if_failure 5 10 sudo ./bin/aks-engine generate $AZURESTACK_CONFIGURATION

log_output -i "ARM template generated at $PWD/_output/$MASTER_DNS_PREFIX directory. Now changing current path to given arm template directory."
cd $PWD/_output/$MASTER_DNS_PREFIX 

log_output -i "Deploy the template."
az group deployment create -g $RESOURCE_GROUP_NAME --template-file azuredeploy.json --parameters azuredeploy.parameters.json > /dev/null

log_output -i "Kubernetes cluster deployment went through fine."