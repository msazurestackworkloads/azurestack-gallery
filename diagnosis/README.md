# Troubleshooting

This short [guide](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) from the Azure's AKS Engine team has a good high level explanation of how AKS Engine interacts with the Azure Resource Manager (ARM) and lists a few potential issues that can cause AKS Engine commands to fail.

Please refer to this [article](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-solution-template-kubernetes-trouble) for specifics about how the `Kubernetes Cluster` marketplace item works on Azure Stack.

Follow this [article](https://docs.microsoft.com/azure-stack/user/azure-stack-version-profiles-azurecli2) to configure and login to your Azure Stack instance using Azure CLI

## Gathering logs

The Bash scripts on this directory are aim to simplify the collection of relevant logs from your Kubernetes cluster. Instead of SSH-ing into the cluster nodes, you can simply download and extract the latest [release] and execute script `getkuberneteslogs.sh`  

These are the logs retrieved by the script:

- Microsoft Azure Linux Agent (waagent) logs
- Custom Script Extension logs
- Running kube-system container metadata
- Running kube-system container logs
- Kubelet service status and journal
- Etcd service status and journal
- Gallery item's DVM logs
- kube-system Snapshot

## Required Parameters 

-u, --user           - The administrator username for the cluster VMs
-i, --identity-file  - RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')
-g, --resource-group - Kubernetes cluster resource group

## Optional Parameters

 -n, --user-namespace       - Collect logs from containers in the specified namespaces (kube-system logs are always collected)
--api-model                 - User can upload the apimodel.json file to Storage account
--upload-logs               - Persists retrieved logs in an Azure Stack storage account. Logs can be found in "KubernetesLogs" resource group.
--disable-host-key-checking - Sets SSH's StrictHostKeyChecking option to "no" while the script executes. Only use in a safe environment.
