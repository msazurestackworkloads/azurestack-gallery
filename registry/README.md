# Docker Container Registry Marketplace Item

## Install Gallery Item

### Build Package

Use `make release` to create an Azure Gallery Package (.azpkg) for Docker Container Registry solution template. The package will be placed in the `_out` directory. Upload the package to a blob container in a storage account, and make sure to change the access policy of the blob to enable anonymous access.

### Side-load Package

Update the admin credentials and storage account information in the `gallery.ps1` script, and run it to connect to the management endpoint and install package.

```powershell
Scripts\gallery.ps1
```

## Solution Pre-requisites

### Create Self-signed Certificate (optional)

Update certificate information in the "self-signed.ps1" script, and run it to create a new certificate in `pfx` format and and export it. If an existing certificate is preferred, use the `Export-PfxCertificate` command instead to export the certificate.

```powershell
Scripts\self-signed.ps1
```

This certificate will be uploaded to a Key Vault instance in a subsequent step, and used by the private docker registry virtual machine.

### Create Backend Storage Account and Key Vault

Update the tenant information in the `connect.ps1` script, and run it to connect to tenant space.

```powershell
Scripts\connect.ps1
```

Update variables instance, resources, certificate and docker registry user credentials information in the "pre-reqs.ps1" script, and run it to create the backend Storage Account and Key Vault instance. The "Certificate URL" and "Certificate thumbprint" from the script output, together with the created storage account and Key Vault information, will be used in the subsequent step to deploy the private docker registry.

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
