# Troubleshooting

This short [guide](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) from the Azure's AKS Engine team has a good high level explanation of how AKS Engine interacts with the Azure Resource Manager (ARM) and lists a few potential issues that can cause AKS Engine commands to fail.

Please refer to this [article](https://aka.ms/AzsK8sLogs) for specifics about how the Kubernetes marketplace gallery item deploys a Kubernetes cluster on Azure Stack.

# Gathering logs

The Bash scripts on this directory are aim to simplify the log collection process. Instead of SSH-ing into the cluster nodes, you can simply download and execute script `getkuberneteslogs.sh` and wait for the logs to be saved back into your workstation.  

These are the logs retrieved by the script:

- Microsoft Azure Linux Agent (waagent) logs
- Cloud-init logs
- Custom Script Extension logs
- Running Docker container metadata
- Running Docker container logs
- Kubelet service status and journal
- Etcd service status and journal
- Gallery item's DVM logs

Take into account that the current version of `getkuberneteslogs.sh` will momentarily upload your private SSH key to the cluster.