# Microsoft Azure Container Service Engine

The Azure Container Service Engine (acs-engine) generates ARM (Azure Resource Manager) templates for Docker enabled clusters on Microsoft Azure.

This [fork](https://github.com/msazurestackworkloads/acs-engine) should be used to deploy Kubernetes cluster to Microsoft Azure Stack instances. At the moment, only the `generate` and `deploy` commands are supported on Azure Stack. We are working on adding support for the `scale` and `upgrade` commands.

# How to Deploy a Kubernetes Cluster

The easiest way to deploy a Kubernetes cluster is through the Kubernetes Cluster marketplace item. This marketplace item wraps acs-engine in order to simplify its usage. Behind the scenes, it deploys a Linux virtual machine, clones Azure Stack's fork, generate the ACS-Engine templates and deploys them from the Linux virtual machine.

1. You need an Azure Service Principal (applications) from your tenant Azure Active Directory (Azure portal)
    1. Create a SPN in your AAD in Azure portal ([instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#create-an-azure-active-directory-application))
    2. Make sure your SPN has the [required permissions](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#check-azure-active-directory-permissions)
2. SSH keys are required to remote into the cluster nodes. Follow this [link](https://github.com/msazurestackworkloads/acs-engine/blob/master/docs/ssh.md#ssh-key-generation) if you need help creating the SSH keys
3. Add/upgrade the following items from Marketplace Management
    - Canonical's Ubuntu Server 16.04 LST
    - Custom Script for Linux 2.0
    - Kubernetes Cluster
4. Ensure that you have a valid subscription in your Azure Stack tenant portal (with enough Public IPs quota to try out a few applications)
5. Ensuring that the service principal has [access to the subscription](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#assign-application-to-role) in your Azure Stack tenant portal.
6. Deploy the Kubernetes Cluster marketplace item. This should roughly take 30 mins.

# Troubleshooting:
- If you hit any issues during cluster deployment, log into the deployment virtual machine named "vmd-(resource group name)" and check the deployment log file `/var/log/azure/acsengine-kubernetes-dvm.log`

- If you need to deploy a new cluster, make sure to modify `masterProfileDnsPrefix` so that you can have a unique DNS name.

