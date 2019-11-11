mkdir _out
$manifest = (Get-Location).Path + "\template\manifest.json"
hack\packager\AzureGalleryPackager.exe -m $manifest -o _out