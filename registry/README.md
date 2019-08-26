# Docker Container Registry Marketplace Item

## Install Gallery Item

### Build Package

Create `azpkg` and upload to a ßstorage account.

```powershell
PackageGenerator\AzureGalleryPackager.exe -m <path-to-manifest.json> -o <output-dir>
```

### Side-load Package

Connect to management endpoint and install package.

```powershell
Scripts\gallery.ps1
```

## Solution Pre-requisites

### Create Self-signed Certificate (optional)

```powershell
Scripts\self-signed.ps1
```

### Create Backend Storage and Key Vault

Connect to tenant space

```powershell
Scripts\connect.ps1
```

Create backend storage and key vault

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
