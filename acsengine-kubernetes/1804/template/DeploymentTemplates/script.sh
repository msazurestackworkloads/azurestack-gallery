set -e

echo "Starting test for acsengine-kubernetes-dvm."
date

echo "Running as:"
whoami

sleep 20

# Script parameters
RESOURCE_GROUP_NAME=${1}
TENANT_ENDPOINT=${2}
TENANT_ID=${3}
TENANT_SUBSCRIPTION_ID=${4}
ADMIN_USERNAME=${5}
MASTER_DNS_PREFIX=${6}
AGENT_COUNT=${7}
SPN_CLIENT_ID=${8}
SPN_CLIENT_SECRET=${9}
K8S_AZURE_CLOUDPROVIDER_VERSION=${10}
REGION_NAME=${11}
SSH_PUBLICKEY="${12} ${13} ${14}"

echo "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "TENANT_ENDPOINT: $TENANT_ENDPOINT"
echo "TENANT_ID: $TENANT_ID"
echo "TENANT_SUBSCRIPTION_ID: $TENANT_SUBSCRIPTION_ID"
echo "ADMIN_USERNAME: $ADMIN_USERNAME"
echo "MASTER_DNS_PREFIX: $MASTER_DNS_PREFIX"
echo "AGENT_COUNT: $AGENT_COUNT"
echo "SPN_CLIENT_ID: $SPN_CLIENT_ID"
echo "SPN_CLIENT_SECRET: $SPN_CLIENT_SECRET"
echo "K8S_AZURE_CLOUDPROVIDER_VERSION: $K8S_AZURE_CLOUDPROVIDER_VERSION"
echo "REGION_NAME: $REGION_NAME"
echo "SSH_PUBLICKEY: $SSH_PUBLICKEY"

echo 'Printing the system information'
sudo uname -a

retrycmd_if_failure() { retries=$1; wait=$2; shift && shift; for i in $(seq 1 $retries); do ${@}; [ $? -eq 0  ] && break || sleep $wait; done; echo Executed \"$@\" $i times; }

echo "Update the system."
retrycmd_if_failure 5 10 sudo apt-get update -y

echo "Installing pax for string manipulation."
retrycmd_if_failure 5 10 sudo apt-get install pax -y

echo "Installing jq for JSON manipulation."
retrycmd_if_failure 5 10 sudo apt-get install jq -y

echo "Update the system."
retrycmd_if_failure 5 10 sudo apt-get update -y

echo "Installing Azure CLI"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/radhikagupta5/AzureStack-QuickStart-Templates/radhikgu-acs/101-acsengine-kubernetes-1805/DeploymentTemplates/install.py"
wget $INSTALL_SCRIPT_URL
if ! command -v python >/dev/null 2>&1
then
  echo "ERROR: Python not found. 'command -v python' returned failure."
  echo "If python is available on the system, add it to PATH. For example 'sudo ln -s /usr/bin/python3 /usr/bin/python'"
  exit 1
fi
chmod 777 install.py
echo "Running install script to install Azure CLI."
retrycmd_if_failure 5 10 python install.py
echo "Completed installing AzureCLI."

echo 'Import the root CA certificate to python store.'
sudo cat /var/lib/waagent/Certificates.pem >> /root/lib/azure-cli/lib/python2.7/site-packages/certifi/cacert.pem
sudo cat /var/lib/waagent/Certificates.pem >> ~/lib/azure-cli/lib/python2.7/site-packages/certifi/cacert.pem

echo 'Import the root CA to store.'
sudo cp /var/lib/waagent/Certificates.pem /usr/local/share/ca-certificates/azsCertificate.crt
sudo update-ca-certificates

echo 'Retrieve the AzureStack root CA certificate thumbprint'
THUMBPRINT=$(openssl x509 -in /var/lib/waagent/Certificates.pem -fingerprint -noout | cut -d'=' -f 2 | tr -d :)
echo 'Thumbprint for AzureStack root CA certificate:' $THUMBPRINT

echo "Cloning the ACS-Engine repo/branch: msazurestackworkloads, acs-engine-v0140-ci"
git clone https://github.com/msazurestackworkloads/acs-engine -b acs-engine-v0140-ci
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

PATTERN="https://management.$REGION_NAME."
if `echo $TENANT_ENDPOINT | grep $PATTERN 1>/dev/null 2>&1`
then
  echo "Validated that tenant endpoint: $TENANT_ENDPOINT is of correct format."
else
  echo "The tenant endpoint: $TENANT_ENDPOINT is not of correct format. Exiting!"
  exit 1
fi

EXTERNAL_FQDN=${TENANT_ENDPOINT##*$PATTERN}
SUFFIXES_STORAGE_ENDPOINT=$REGION_NAME.$EXTERNAL_FQDN
SUFFIXES_KEYVAULT_DNS=.vault.$REGION_NAME.$EXTERNAL_FQDN
FQDN_ENDPOINT_SUFFIX=cloudapp.$EXTERNAL_FQDN
ENVIRONMENT_NAME=AzureStackCloud

echo 'Register to the cloud.'

/root/bin/az cloud register \
  --name $ENVIRONMENT_NAME \
  --endpoint-resource-manager $TENANT_ENDPOINT \
  --suffix-storage-endpoint $SUFFIXES_STORAGE_ENDPOINT \
  --suffix-keyvault-dns $SUFFIXES_KEYVAULT_DNS \
  --endpoint-vm-image-alias-doc 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/master/arm-compute/quickstart-templates/aliases.json' \
  --profile 2017-03-09-profile

echo "Set the current cloud to be $ENVIRONMENT_NAME"
/root/bin/az cloud set --name $ENVIRONMENT_NAME

ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=$(/root/bin/az cloud show | jq '.endpoints.activeDirectoryResourceId' | tr -d \")
ENDPOINT_GALLERY=$(/root/bin/az cloud show | jq '.endpoints.gallery' | tr -d \")

echo 'Overriding the default file with the correct values in the API model or the cluster definition.'

if [ -f "examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json" ]
then
	echo "Found azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json."
else
	echo "File azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json does not exist. Exiting..."
	exit 1
fi

echo "Copying the default file API model to $PWD."
sudo cp examples/azurestack/azurestack-kubernetes$K8S_AZURE_CLOUDPROVIDER_VERSION.json azurestack.json
if [ -s "azurestack.json" ] ; then
	echo "Found azurestack.json in $PWD and is > 0 bytes"
else
	echo "File azurestack.json does not exist in $PWD or is zero length."
	exit 1
fi

sudo cat azurestack.json | jq --arg THUMBPRINT $THUMBPRINT '.properties.cloudProfile.resourceManagerRootCertificate = $THUMBPRINT' | \
jq --arg ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID '.properties.cloudProfile.serviceManagementEndpoint = $ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID' | \
jq --arg TENANT_ENDPOINT $TENANT_ENDPOINT '.properties.cloudProfile.resourceManagerEndpoint = $TENANT_ENDPOINT' | \
jq --arg ENDPOINT_GALLERY $ENDPOINT_GALLERY '.properties.cloudProfile.galleryEndpoint = $ENDPOINT_GALLERY' | \
jq --arg SUFFIXES_STORAGE_ENDPOINT $SUFFIXES_STORAGE_ENDPOINT '.properties.cloudProfile.storageEndpointSuffix = $SUFFIXES_STORAGE_ENDPOINT' | \
jq --arg SUFFIXES_KEYVAULT_DNS $SUFFIXES_KEYVAULT_DNS '.properties.cloudProfile.keyVaultDNSSuffix = $SUFFIXES_KEYVAULT_DNS' | \
jq --arg FQDN_ENDPOINT_SUFFIX $FQDN_ENDPOINT_SUFFIX '.properties.cloudProfile.resourceManagerVMDNSSuffix = $FQDN_ENDPOINT_SUFFIX' | \
jq --arg REGION_NAME $REGION_NAME '.properties.cloudProfile.location = $REGION_NAME' | \
jq --arg MASTER_DNS_PREFIX $MASTER_DNS_PREFIX '.properties.masterProfile.dnsPrefix = $MASTER_DNS_PREFIX' | \
jq '.properties.agentPoolProfiles[0].count'=$AGENT_COUNT | \
jq --arg ADMIN_USERNAME $ADMIN_USERNAME '.properties.linuxProfile.adminUsername = $ADMIN_USERNAME' | \
jq --arg SSH_PUBLICKEY "${SSH_PUBLICKEY}" '.properties.linuxProfile.ssh.publicKeys[0].keyData = $SSH_PUBLICKEY' | \
jq --arg SPN_CLIENT_ID $SPN_CLIENT_ID '.properties.servicePrincipalProfile.clientId = $SPN_CLIENT_ID' | \
jq --arg SPN_CLIENT_SECRET $SPN_CLIENT_SECRET '.properties.servicePrincipalProfile.secret = $SPN_CLIENT_SECRET' > azurestack_temp.json

if [ -s "azurestack_temp.json" ] ; then
	echo "Found azurestack_temp.json in $PWD and is > 0 bytes"
else
	echo "File azurestack_temp.json does not exist in $PWD or is zero length. Error happend during building the input API model or cluster definition."
	exit 1
fi

sudo mv azurestack_temp.json azurestack.json
echo "Done building the API model based on the stamp information."

echo 'Login to the cloud.'
/root/bin/az login \
  --service-principal \
  --username $SPN_CLIENT_ID \
  --password $SPN_CLIENT_SECRET \
  --tenant $TENANT_ID

echo "Setting subscription to $TENANT_SUBSCRIPTION_ID"
/root/bin/az account set --subscription $TENANT_SUBSCRIPTION_ID

MYDIR=$PWD
echo "Current directory is: $MYDIR"

echo "Generate and Deploy the template using the API model in resource group $MASTER_DNS_PREFIX."
sudo ./bin/acs-engine deploy --resource-group $RESOURCE_GROUP_NAME --azure-env $ENVIRONMENT_NAME --location $REGION_NAME --subscription-id $TENANT_SUBSCRIPTION_ID --client-id $SPN_CLIENT_ID --client-secret $SPN_CLIENT_SECRET --auth-method client_secret --api-model azurestack.json

echo "Templates output directory is $PWD/_output/$MASTER_DNS_PREFIX"

echo "Ending test for acsengine-kubernetes-dvm."



