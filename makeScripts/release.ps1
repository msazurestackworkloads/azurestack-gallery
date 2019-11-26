mkdir _out

Invoke-WebRequest aka.ms/azurestackmarketplaceitem -o _out\packager.zip
Expand-Archive _out\packager.zip -DestinationPath _out

$src = (Get-Location).Path + "\_out\Azure Stack Marketplace Item Generator and Sample\AzureGalleryPackageGenerator\"
$dst = (Get-Location).Path + "\_out\packager\"
Move-Item -Path $src -Destination $dst

$manifest_k8s = (Get-Location).Path + "\kubernetes\template\manifest.json"
_out\packager\AzureGalleryPackager.exe -m $manifest_k8s -o _out

$manifest_registry = (Get-Location).Path + "\registry\manifest.json"
_out\packager\AzureGalleryPackager.exe -m $manifest_registry -o _out