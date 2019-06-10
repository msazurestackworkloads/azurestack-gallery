# Troubleshooting

Creating a Kubernetes cluster from Azure Stack's Marketplace is internally a two phase process. A first ARM deployment creates a _deployment virtual machine_ (aka DVM) in the cluster's resource group. While provisioning the DVM, a custom script extensions (aka CSE) will initiate the second phase by executing [AKS Engine's](https://github.com/Azure/aks-engine) _deploy_ command. This command triggers a second ARM deployment that will effectively create the Kubernetes cluster.

If a failure happens during the DVM deployment or its CSE execution, the Azure Stack portal will show an exit code that corresponds an entry in the [exit codes table](#exit-codes-table) .

If a failure happens during the Kubernetes cluster deployment, then AKS Engine's [documentation](https://github.com/Azure/aks-engine/blob/master/docs/howto/troubleshooting.md) should provide the most up-to-date troubleshooting information.

If the Azure Stack portal does not provide enough information for you to troubleshoot or overcome a deployment failure, the next step is to dig into the VM logs. To manually retrieve the deployment logs, you typically need to connect to one of the virtual machines. A simpler alternative approach would be to download and run the following [Bash script](https://aka.ms/AzsK8sLogCollectorScript). This script connects to the DVM and cluster nodes, collects relevant system and cluster logs, and downloads them back to your workstation. The log collector script will also look for errors in the log files and include troubleshooting steps if it happens to find a known issue. Download the latest version of the script to increase chances of finding these known issues.

## Exit codes table

| Name | Exit Code | Description |
|------|-----------|-------------|
| ERR_APT_INSTALL_TIMEOUT | 9  | Timeout waiting for `apt-get install` to complete |
| ERR_AKSE_DOWNLOAD | 10 | Failure downloading AKS Engine binaries from GitHub |
| ERR_AKSE_GENERATE | 11 | Failure thrown by AKS Engine's `generate` operation |
| ERR_AKSE_DEPLOY | 12 | Failure thrown by AKS Engine's `deploy` operation |
| ERR_TEMPLATE_DOWNLOAD | 13 | Failure downloading AKS-Engine cluster definition |
| ERR_CACERT_INSTALL | 20 | Failure handling CA certificate |
| ERR_MS_GPG_KEY_DOWNLOAD_TIMEOUT | 26 | Timeout waiting for Microsoft's GPG key download |
| ERR_METADATA_ENDPOINT | 30 | Non-successful call to Azure Stack's metadata endpoint |
| ERR_API_MODEL | 40 | Failure customizing API model |
| ERR_AZS_CLOUD_REGISTER | 50 | Command `az cloud register` did not succeed |
| ERR_AZS_CLOUD_ENVIRONMENT | 51 | Command `az cloud environment` did not succeed |
| ERR_AZS_CLOUD_PROFILE | 52 | Command `az cloud profile` did not succeed |
| ERR_AZS_LOGIN_AAD | 53 | Error trying to log into AAD environment |
| ERR_AZS_LOGIN_ADFS | 54 | Error trying to log into ADFS environment |
| ERR_AZS_ACCOUNT_SUB | 55 | Error setting account's default subscription |
| ERR_APT_UPDATE_TIMEOUT | 99 | Timeout waiting for `apt-get update` to complete |