#requires -runasadministrator

<#
.Synopsis
  The script provide functionality to install a marketplace item from given URL.

.Description
  The script provide functionality to install a marketplace item from given URL.

.Parameter AzureStackDomainName
  Fully qualified domain name of Azure Stack instance.

.Parameter AdminUserName
  Admin username.

.Parameter AdminPassword
  Admin password.

.Parameter TenantId
  Tenant ID of Azure Stack.

.Parameter MarketplaceUri
  Marketplace package download URL.

.Parameter EnvironmentName
  Name of the environment.

.Example
   gallery.ps1 -AzureStackDomainName local.microsoft.com 
               -AdminUserName admin@localazurestack.onmicrosoft.com 
               -AdminPassword <Login Password> 
               -TenantId 00000000-0000-0000-0000-000000000000 
               -MarketplaceUri https://local.blob.core.windows.net/marketplaceblob/Microsoft.AzureStackDockerContainerRegistry.1.0.0.azpkg
#>
Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Fully qualified domain name of Azure Stack instance.")]
    [string] $AzureStackDomainName,
    [Parameter(Mandatory = $true, HelpMessage = "Admin username.")]
    [string] $AdminUserName,
    [Parameter(Mandatory = $true, HelpMessage = "Admin password")]
    [string] $AdminPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Tenant ID of Azure Stack.")]
    [string] $TenantId,
    [Parameter(Mandatory = $true, HelpMessage = "Marketplace package download URL.")]
    [string] $MarketplaceUri,
    [Parameter(Mandatory = $false, HelpMessage = "Name of the environment.")]
    [string] $EnvironmentName = "AzureStackAdmin"
)

$environment = Get-AzureRmEnvironment -Name $EnvironmentName 
if ($null -eq $environment)
{
    $armEndPoint="https://adminmanagement.$AzureStackDomainName/"
    $environment = Add-AzureRmEnvironment -Name $EnvironmentName -ARMEndpoint $armEndPoint -ErrorAction Stop
}
else
{
    Write-Host "Environment($EnvironmentName) is already in use." 
}

$secpasswd = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($AdminUserName, $secpasswd) 
Login-AzureRmAccount -Credential $mycreds -EnvironmentName $EnvironmentName -TenantId $TenantId

# Deploy package
#$PKG_SA_NAME=""
#$PKG_SA_CONTAINER=""
#$PKG_VERSION=""
#"https://$PKG_SA_NAME.blob.$AzureStackDomainName/$PKG_SA_CONTAINER/Microsoft.AzureStackDockerContainerRegistry.$PKG_VERSION.azpkg"

Add-AzsGalleryItem -Force -GalleryItemUri $MarketplaceUri

# Remove package
# Remove-AzsGalleryItem -Force -Name "Microsoft.AzureStackDockerContainerRegistry.$PKG_VERSION"
