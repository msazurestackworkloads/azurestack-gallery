# Troubleshooting

This short [guide](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) from the Azure's AKS Engine team has a good high level explanation of how AKS Engine interacts with the Azure Resource Manager (ARM) and lists a few potential issues that can cause AKS Engine commands to fail.

Please refer to this [article](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-solution-template-kubernetes-trouble) for specifics about how the `Kubernetes Cluster` marketplace item works on Azure Stack.

##Prerequisites:
1.	Enable Azure CLI on AzureStack (https://docs.microsoft.com/en-us/azure-stack/user/azure-stack-version-profiles-azurecli2?view=azs-1908) 
2.	Use az login –service-principal -u <spn-client-id> -p <spn-client-password> --tenant <tenant-id>

## Gathering logs

The Bash scripts on this directory are aim to simplify the collection of relevant logs from your Kubernetes cluster. Instead of SSH-ing into the cluster nodes, you can simply download zip file and execute script `getkuberneteslogs.sh` and wait for the logs to be saved back into your workstation.  

These are the logs retrieved by the script:

- Microsoft Azure Linux Agent (waagent) logs
- Cloud-init logs
- Custom Script Extension logs
- Running Docker container metadata
- Running Docker container logs
- Kubelet service status and journal
- Etcd service status and journal
- Gallery item's DVM logs
- Cluster Snapshot

Log collection process can upload logs to storage account when --upload-logs parameter is used, the logs can be found in "KubernetesLogs" resource group.

After the log collection process is complete, the script will also try to look for common issues or misconfigurations. If any of those are found, they will be saved in file `ALL_ERRORS.txt`.