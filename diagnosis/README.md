# Troubleshooting AKS Engine on Azure Stack

This short [guide](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) from Azure's AKS Engine team has a good high level explanation of how AKS Engine interacts with the Azure Resource Manager (ARM) and lists common reasons that can cause AKS Engine commands to fail. That guide applies to Azure Stack as well as it ships with its own ARM instance. If you are facing a problem that is not part of this guide, then you will need extra information to figure out the root cause.

Typically, to collect logs from servers you manage, you have to start a remote session using SSH and browse for relevant log files. The scripts in this directory are aim to simplify the collection of relevant logs from your Kubernetes cluster. Just download/unzip the latest [release](https://github.com/msazurestackworkloads/azurestack-gallery/releases/tag/diagnosis-v0.1.2) and execute script `getkuberneteslogs.sh`.

> Before you execute `getkuberneteslogs.sh`, make sure that you can login to your Azure Stack instance using `Azure CLI`. Follow this [article](https://docs.microsoft.com/azure-stack/user/azure-stack-version-profiles-azurecli2) to learn how to configure Azure CLI to manage your Azure Stack cloud.

The logs retrieved by `getkuberneteslogs.sh` are the following:

- Log files in directory `/var/log/azure/`
- Log files in directory `/var/log/kubeaudit` (kube audit logs)
- Log file `/var/log/waagent.log` (waagent)
- Log file `/var/log/azure/deploy-script-dvm.log` (if deployed using Azure Stack's Kubernetes Cluster marketplace item)
- Static manifests in directory `/etc/kubernetes/manifests`
- Static addons in directory `/etc/kubernetes/addons`
- kube-system containers metadata and logs
- kubelet status and journal
- etcd status and journal
- docker status and journal
- kube-system snapshot
- Kubernetes cloud provider logs

Some additional logs are retrieved for Windows nodes:

 - Log file `c:\Azure\CustomDataSetupScript.log`
 - kube-proxy status and journal
 - containerd status and journal
 - azure-vnet log and azure-vnet-telemetry log
 - ETW events for docker
 - ETW events for Hyper-V

## Required Parameters

`-u, --user`           - The administrator username for the cluster VMs

`-i, --identity-file`  - RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')

`-g, --resource-group` - Kubernetes cluster resource group

## Optional Parameters

`--disable-host-key-checking`  - Sets SSH's `StrictHostKeyChecking` option to `no` while the script executes. Only use in a safe environment.

`--upload-logs`                - Persists retrieved logs in an Azure Stack storage account. Logs can be found in `KubernetesLogs` resource group.

`--api-model`                  - Persists apimodel.json file in an Azure Stack Storage account. 
                                 Upload apimodel.json file to storage account happens when `--upload-logs` parameter is also provided.

`-h, --help`                   - Print script usage
