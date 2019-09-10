$FQDN=""

# Admin Login
$TENANT_ID=""
$ADMIN_USER=""
$ADMIN_PASS=""

Add-AzureRmEnvironment -ARMEndpoint "https://adminmanagement.$FQDN/" -Name "AzureStackAdmin"
$secpasswd = ConvertTo-SecureString $ADMIN_PASS -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($ADMIN_USER, $secpasswd) 
Login-AzureRmAccount -Credential $mycreds -EnvironmentName "AzureStackAdmin" -TenantId $TENANT_ID

# Deploy package
$PKG_SA_NAME=""
$PKG_SA_CONTAINER=""
$PKG_VERSION=""

Add-AzsGalleryItem -Force -GalleryItemUri "https://$PKG_SA_NAME.blob.$FQDN/$PKG_SA_CONTAINER/Microsoft.AzureStackDockerContainerRegistry.$PKG_VERSION.azpkg"

# Remove package
Remove-AzsGalleryItem -Force -Name "Microsoft.AzureStackDockerContainerRegistry.$PKG_VERSION"
