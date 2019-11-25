# Docker Container Registry Marketplace Item

## Install Gallery Item

### Build Package

Use the `make release` command to create `azpkg` file for Docker Container Registry Marketplace Item, and find it in the "_out" folder. Upload the file to a blob container in a storage account, and make sure to change the access policy of the blob to enable anonymous access.

### Side-load Package

Update admin credential and storage account information in the `gallery.ps1` script, and use it to connect to management endpoint and install package.

```powershell
Scripts\gallery.ps1
```

## Solution Pre-requisites

### Create Self-signed Certificate

Update certificate information in the "self-signed.ps1" script, and use it to create a new certificate in `pfx` formatand and export it. If an existing certificate is preferred, use the `Export-PfxCertificate` command instead to export the certificate.

```powershell
Scripts\self-signed.ps1
```

This certificate will be uploaded to a key vault in a following step, and used by the private docker registry vm.

### Create Backend Storage and Key Vault

Update the tenant information in the `connect.ps1` script, and usse it to connect to tenant space.

```powershell
Scripts\connect.ps1
```

Update instance, resources, certificate and docker registry user credential information in the "pre-reqs.ps1" script, and use it to create backend storage and key vault. The "Certificate URL" and "Certificate thumbprint" from script console output, together with the created storage account and key vault information, will be used in the follow step to create deployment for the private docker registry.

```powershell
Scripts\pre-reqs.ps1
```

## Deploy Solution

From tenant portal

```
Create a resource -> Compute -> Docker Container Registry
```

Sample parameters

```
DeploymentTemplate\azuredeploy.parameters-example.json
```

## Logs

Container logs located in directory `/var/lib/docker/containers/`

Query all logs: `cat /var/lib/docker/containers/*/*-json.log | grep "authentication failure"`

## TODO

- Review strings in `Strings\resources.resjson`
- Review strings in `manifest.json`
- Replace `Screenshots\screenshot.png`
- Replace `Icons\*.png`
- Review UI labels in `DeploymentTemplates\createUiDefinition`
- Add tooltips to UI elements to `DeploymentTemplates\createUiDefinition` if needed
- Use AKS Base Image
