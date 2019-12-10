# Docker Container Registry Marketplace Item

## Install Gallery Item

### Prepare Package

Use `make release` to create an Azure Gallery Package (.azpkg) for the Docker Container Registry solution template. The package will be placed in the `_out` directory. Upload the package to a BLOB container in an Azure Storage Account with anonymous access enabled.

### Side-load Package

Update the admin credentials and storage account information in `gallery.ps1`, and run it to connect to the management endpoint and install the package in your Azure Stack instance.

```powershell
Scripts\gallery.ps1
```

## Solution Pre-requisites

### Create Self-signed Certificate (optional)

Update the certificate information in `self-signed.ps1`, and run it to create a new `pfx` self-signed certificate. If you already have a certificate, you can skip this step.

```powershell
Scripts\self-signed.ps1
```

This certificate will be uploaded to a Key Vault instance in a subsequent step, and then consumed by the private docker registry.

### Create Backend Storage Account and Key Vault

Update the tenant information in `connect.ps1` and run it to connect to the tenant space.

```powershell
Scripts\connect.ps1
```

Set your environment information in `pre-reqs.ps1` and run it to create and populate the required backend Storage Account and Key Vault instance. Take note of the script output as it will be used later to deploy the private docker registry.

```powershell
Scripts\pre-reqs.ps1
```

## Deploy Solution

From the tenant portal, go to:

```
Create a resource -> Compute -> Docker Container Registry
```

## Logs

The container registry logs are located in directory `/var/lib/docker/containers/`

To query all logs: `cat /var/lib/docker/containers/*/*-json.log | grep "authentication failure"`
