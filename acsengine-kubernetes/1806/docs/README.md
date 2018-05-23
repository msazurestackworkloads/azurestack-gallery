The Azure Container Service Engine (acs-engine) generates ARM (Azure Resource Manager) templates for Docker enabled clusters on Microsoft Azure with your choice of DC/OS, Kubernetes, Swarm Mode, or Swarm orchestrators.

We have modified acs-engine to work with AzureStack. Please follow the steps below try Kubernetes
================================================================================
This template deploys a Linux VM, clones and AzureStack forked ACS-Engine repo/branch, generate the ACS-Engine templates and deploys them from the linux VM.

1) Prerequistes:
	a) You need to be able to create SPN (applications) in your tenant AAD (in Azure portal) for Kubernetes deployment. 
	   Following can be used to check if you have appropriate permissions:
	   https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#check-azure-active-directory-permissions

	b) Create an SPN in your AAD in Azure portal: 
	   https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#create-an-azure-active-directory-application

	b) SSH key is required to login to the Linux VMs. You would need to pass the public key to the template inputs.
	   https://github.com/msazurestackworkloads/acs-engine/blob/master/docs/ssh.md#ssh-key-generation

	c) Ensure that following Ubuntu image is added from marketplace,
    Publisher = "Canonical"
    Offer = "UbuntuServer"
    SKU = "16.04-LTS"
    Version = "16.04.201802220"
    OSType = "Linux"

	d) You also need to download Custom Script for Linux, 2.0.3 from the marketplace.

	e) Add the marketplace item, azpkg to admin portal using:
	
	Add-AzureRmEnvironment -Name "AzureStackUser" -ArmEndpoint "https://adminmanagement.local.azurestack.external"
	
	$TenantID="5308332c-26e2-4fdb-9beb-e883a706bc08"

	$UserName='ciserviceadmin@msazurestack.onmicrosoft.com'

	$Password='Password'| ConvertTo-SecureString -Force -AsPlainText
	
	$Credential= New-Object PSCredential($UserName,$Password)
	
	Login-AzureRmAccount -EnvironmentName "AzureStackUser" -TenantId $TenantID -Credential $Credential

	Select-AzureRmSubscription -Subscription "Default Provider Subscription"

	Add-AzsGalleryItem -GalleryItemUri "https://azurestacktemplate.blob.core.windows.net/kubernetes-1804/Microsoft.AzureStackKubernetesCluster.0.1.0.azpkg" 

	Please wait atleast 5 mins for the item to show up in marketplace in Tenant portal. It will show up with the name "Kubernetes Cluster".
	
	If you have already added the marketplace item once don't forget to remove it first to update to new one:
	Remove-AzsGalleryItem -Name "Microsoft.AzureStackKubernetesCluster.0.1.0"

2) Ensure that you have a valid subscription in your AzureStack tenant portal (with enough public IP quota to try few applications).

3) Ensuring that the service principal has access to the subcription in your AzureStack tenant portal.
   https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#assign-application-to-role

4) Deploy the marketplace item. This should roughly take 30 mins.
Troubleshooting:
	a) If you hit any issues with deployment first thing to check is: 
	
	Login to the deployment VM with name "vmd-(resource group name)" using Putty/SSH and read the following logs:
		
	/var/log/azure/acsengine-kubernetes-dvm.log

5) If you need to deploy ANOTHER deployment, modify masterProfileDnsPrefix (so that you can have a unique DNS name) and repeat all the above steps.

6) Try a few applications by installing Helm

Helm Installation: https://github.com/kubernetes/helm/blob/master/docs/install.md#from-script

Wordpress Installation (using Helm): helm install stable/wordpress

================================================================================

Here are some important links:
1) Modifed ACS-Engine repo: 
	https://github.com/msazurestackworkloads/acs-engine/tree/acs-engine-v0140

2) Linux binary: 
	https://github.com/msazurestackworkloads/acs-engine/tree/acs-engine-v0140/examples/azurestack/acs-engine.tgz

3) Example of working JSON (API model): 
	https://github.com/msazurestackworkloads/acs-engine/tree/acs-engine-v0140/examples/azurestack/azurestack-kubernetes1.7.json

4) To learn more about generating templates using ACS-Engine refer to ACS Engine: 
	https://github.com/msazurestackworkloads/acs-engine/blob/master/docs/kubernetes.md



