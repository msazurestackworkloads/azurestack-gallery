# Troubleshooting

This short [guide](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) from the Azure's AKS Engine team has a good high level explanation of how AKS Engine interacts with the Azure Resource Manager (ARM) and lists a few potential issues that can cause AKS Engine commands to fail.

Please refer to this [article](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-solution-template-kubernetes-trouble) for specifics about how the Kubernetes marketplace gallery item deploys a Kubernetes cluster on Azure Stack.

## Gathering logs

The Bash scripts on this directory are aim to simplify the collection of relevant logs from your Kubernetes cluster. Instead of SSH-ing into the cluster nodes, you can simply download and execute script `getkuberneteslogs.sh` and wait for the logs to be saved back into your workstation.  

These are the logs retrieved by the script:

- Microsoft Azure Linux Agent (waagent) logs
- Cloud-init logs
- Custom Script Extension logs
- Running Docker container metadata
- Running Docker container logs
- Kubelet service status and journal
- Etcd service status and journal
- Gallery item's DVM logs

Please be aware that the log collector script needs to update file `~/.ssh/config` in order to connect to the cluster's worker nodes. While the script will try to back it up and then restore it once the process is complete, it may be a good a idea to create your own copy.

After the log collection process is complete, the script will also try to look for common issues or misconfigurations. If any of those are found, they will be saved in file `ALL_ERRORS.txt`.