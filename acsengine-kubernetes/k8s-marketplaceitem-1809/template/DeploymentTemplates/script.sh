set -e

echo "Starting deploying Kubernetes cluster"
date

echo "Running as:"
whoami

sleep 20

# Script parameters
echo "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "PUBLICIP_DNS: $PUBLICIP_DNS"
echo "TENANT_ID: $TENANT_ID"
echo "TENANT_SUBSCRIPTION_ID: $TENANT_SUBSCRIPTION_ID"
echo "ADMIN_USERNAME: $ADMIN_USERNAME"
echo "MASTER_DNS_PREFIX: $MASTER_DNS_PREFIX"
echo "AGENT_COUNT: $AGENT_COUNT"
echo "AGENT_SIZE: $AGENT_SIZE"
echo "MASTER_COUNT: $MASTER_COUNT"
echo "MASTER_SIZE: $MASTER_SIZE"
echo "K8S_AZURE_CLOUDPROVIDER_VERSION: $K8S_AZURE_CLOUDPROVIDER_VERSION"
echo "REGION_NAME: $REGION_NAME"
echo "SSH_PUBLICKEY: $SSH_PUBLICKEY"
echo "PUBLICIP_FQDN: $PUBLICIP_FQDN"
echo "STORAGE_PROFILE: $STORAGE_PROFILE"

echo 'Printing the system information'
sudo uname -a

retrycmd_if_failure() { retries=$1; wait=$2; shift && shift; for i in $(seq 1 $retries); do ${@}; [ $? -eq 0  ] && break || sleep $wait; done; echo Executed \"$@\" $i times; }
check_and_move_azurestack_configuration() {
	if [ -s $1 ] ; then
	echo "Found $1 in $PWD and is > 0 bytes"
	else
		echo "File $1 does not exist in $PWD or is zero length. Error happend during building the input API model or cluster definition."
		exit 1
	fi
	echo "Moving $1 to $2"
	sudo mv $1 $2
	echo "Done building the API model based on the stamp information."
}
echo "Update the system."
retrycmd_if_failure 5 10 sudo apt-get update -y

echo "Installing pax for string manipulation."
retrycmd_if_failure 5 10 sudo apt-get install pax -y

echo "Installing jq for JSON manipulation."
retrycmd_if_failure 5 10 sudo apt-get install jq -y

echo "Installing curl."
retrycmd_if_failure 5 10 sudo apt-get install curl -y

echo "Update the system."
retrycmd_if_failure 5 10 sudo apt-get update -y

echo 'Import the root CA to store.'
sudo cp /var/lib/waagent/Certificates.pem /usr/local/share/ca-certificates/azsCertificate.crt
sudo update-ca-certificates

echo 'Retrieve the AzureStack root CA certificate thumbprint'
THUMBPRINT=$(openssl x509 -in /var/lib/waagent/Certificates.pem -fingerprint -noout | cut -d'=' -f 2 | tr -d :)
echo 'Thumbprint for AzureStack root CA certificate:' $THUMBPRINT

echo "Cloning the ACS-Engine repo/branch: deaborch, acs-engine-v0209-1809"
git clone https://github.com/deaborch/acs-engine -b acs-engine-v0209-1809
cd acs-engine

echo "We are going to use an existing ACS-Engine binary."
echo "Open the zip file from the repo location."
sudo mkdir bin
sudo tar -zxvf examples/azurestack/acs-engine.tgz
sudo mv acs-engine bin/

echo "Checkign if acs-engine binary is available."
if [ -f "./bin/acs-engine" ] ; then
	echo "Found acs-engine.exe"
else
	echo "Missing acs-engine.exe. Exiting!"
	exit 1
fi

EXTERNAL_FQDN="${PUBLICIP_FQDN//$PUBLICIP_DNS.$REGION_NAME.cloudapp.}"
TENANT_ENDPOINT="https://management.$REGION_NAME.$EXTERNAL_FQDN"
echo "TENANT_ENDPOINT: $TENANT_ENDPOINT"

SUFFIXES_STORAGE_ENDPOINT=$REGION_NAME.$EXTERNAL_FQDN
SUFFIXES_KEYVAULT_DNS=.vault.$REGION_NAME.$EXTERNAL_FQDN
FQDN_ENDPOINT_SUFFIX=cloudapp.$EXTERNAL_FQDN
ENVIRONMENT_NAME=AzureStackCloud

METADATA=`curl --retry 10 $TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01`

ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=`echo $METADATA  | jq '.authentication.audiences'[0] | tr -d \"`
ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=`echo $METADATA  | jq '.authentication.loginEndpoint' | tr -d \"`
ENDPOINT_GRAPH_ENDPOINT=`echo $METADATA  | jq '.graphEndpoint' | tr -d \"`
ENDPOINT_GALLERY=`echo $METADATA  | jq '.galleryEndpoint' | tr -d \"`

echo 'Overriding the default file with the correct values in the API model or the cluster definition.'

if [ -f "examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json" ]
then
	echo "Found azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json."
else
	echo "File azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json does not exist. Exiting..."
	exit 1
fi


AZURESTACK_CONFIGURATION_TEMP="${AZURESTACK_CONFIGURATION_TEMP:-azurestack_temp.json}"
AZURESTACK_CONFIGURATION="${AZURESTACK_CONFIGURATION:-azurestack.json}"
echo "Copying the default file API model to $PWD."
sudo cp examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json $AZURESTACK_CONFIGURATION
if [ -s "$AZURESTACK_CONFIGURATION" ] ; then
	echo "Found $AZURESTACK_CONFIGURATION in $PWD and is > 0 bytes"
else
	echo "File $AZURESTACK_CONFIGURATION does not exist in $PWD or is zero length."
	exit 1
fi

STORAGE_PROFILE="${STORAGE_PROFILE:-blobdisk}"
# use blobdisk and AvailabilitySet
if [ "$STORAGE_PROFILE" == "blobdisk" ] ; then
        sudo cat $AZURESTACK_CONFIGURATION | jq --arg AvailabilitySet "AvailabilitySet" '.properties.agentPoolProfiles[0].availabilityProfile=$AvailabilitySet' | \
        jq --arg StorageAccount "StorageAccount" '.properties.agentPoolProfiles[0].storageProfile=$StorageAccount' | \
        jq --arg StorageAccount "StorageAccount" '.properties.masterProfile.storageProfile=$StorageAccount' > $AZURESTACK_CONFIGURATION_TEMP
		check_and_move_azurestack_configuration $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION
fi

sudo cat $AZURESTACK_CONFIGURATION | jq --arg THUMBPRINT $THUMBPRINT '.properties.cloudProfile.resourceManagerRootCertificate = $THUMBPRINT' | \
jq --arg ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID '.properties.cloudProfile.serviceManagementEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID' | \
jq --arg ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT '.properties.cloudProfile.activeDirectoryEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT' | \
jq --arg ENDPOINT_GRAPH_ENDPOINT $ENDPOINT_GRAPH_ENDPOINT '.properties.cloudProfile.graphEndpoint = $ENDPOINT_GRAPH_ENDPOINT' | \
jq --arg TENANT_ENDPOINT $TENANT_ENDPOINT '.properties.cloudProfile.resourceManagerEndpoint = $TENANT_ENDPOINT' | \
jq --arg ENDPOINT_GALLERY $ENDPOINT_GALLERY '.properties.cloudProfile.galleryEndpoint = $ENDPOINT_GALLERY' | \
jq --arg SUFFIXES_STORAGE_ENDPOINT $SUFFIXES_STORAGE_ENDPOINT '.properties.cloudProfile.storageEndpointSuffix = $SUFFIXES_STORAGE_ENDPOINT' | \
jq --arg SUFFIXES_KEYVAULT_DNS $SUFFIXES_KEYVAULT_DNS '.properties.cloudProfile.keyVaultDNSSuffix = $SUFFIXES_KEYVAULT_DNS' | \
jq --arg FQDN_ENDPOINT_SUFFIX $FQDN_ENDPOINT_SUFFIX '.properties.cloudProfile.resourceManagerVMDNSSuffix = $FQDN_ENDPOINT_SUFFIX' | \
jq --arg REGION_NAME $REGION_NAME '.properties.cloudProfile.location = $REGION_NAME' | \
jq --arg MASTER_DNS_PREFIX $MASTER_DNS_PREFIX '.properties.masterProfile.dnsPrefix = $MASTER_DNS_PREFIX' | \
jq '.properties.agentPoolProfiles[0].count'=$AGENT_COUNT | \
jq --arg AGENT_SIZE $AGENT_SIZE '.properties.agentPoolProfiles[0].vmSize=$AGENT_SIZE' | \
jq '.properties.masterProfile.count'=$MASTER_COUNT | \
jq --arg MASTER_SIZE $MASTER_SIZE '.properties.masterProfile.vmSize=$MASTER_SIZE' | \
jq --arg ADMIN_USERNAME $ADMIN_USERNAME '.properties.linuxProfile.adminUsername = $ADMIN_USERNAME' | \
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' | \
jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' >  $AZURESTACK_CONFIGURATION_TEMP

check_and_move_azurestack_configuration $AZURESTACK_CONFIGURATION_TEMP $AZURESTACK_CONFIGURATION
echo "Done building the API model based on the stamp information."

MYDIR=$PWD
echo "Current directory is: $MYDIR"

echo "Deploy the template using the API model in resource group $MASTER_DNS_PREFIX."
sudo ./bin/acs-engine deploy --resource-group $RESOURCE_GROUP_NAME --azure-env $ENVIRONMENT_NAME --location $REGION_NAME --subscription-id $TENANT_SUBSCRIPTION_ID --client-id $SPN_CLIENT_ID --client-secret $SPN_CLIENT_SECRET --auth-method client_secret --api-model $AZURESTACK_CONFIGURATION

echo "Templates output directory is $PWD/_output/$MASTER_DNS_PREFIX"

echo "Ending deploying  Kubernetes cluster."