mkdir _out

Invoke-WebRequest aka.ms/azurestackmarketplaceitem -o _out\packager.zip
Expand-Archive _out\packager.zip -DestinationPath _out

$src = (Get-Location).Path + "\_out\Azure Stack Marketplace Item Generator and Sample\AzureGalleryPackageGenerator\"
$dst = (Get-Location).Path + "\_out\packager\"
Move-Item -Path $src -Destination $dst

$manifest = (Get-Location).Path + "\manifest.json"
_out\packager\AzureGalleryPackager.exe -m $manifest -o _out