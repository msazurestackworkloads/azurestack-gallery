

<#
.Synopsis
    Create a resource group under selected subscription for logged tenant

.Description
    Create a resource group under selected subscription for logged tenant 

.Parameter ResourceGroupName
    Resource group name which needs to be created.

.Example
   New-ResourceGroup -ResourceGroupName "resourcegroupname"
#>
function New-ResourceGroup (
    [string] $ResourceGroupName
)
{
    # RESOURCE GROUP
    # =============================================
    Write-Host "Check if resource group($ResourceGroupName) already exist" 
    Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable doesResourceGroupExist | Out-Null
    if ($doesResourceGroupExist) {
        # Create resource group
        Write-Host "Resource group ($ResourceGroupName) does not exist. Creating a new resource group." 
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location | out-null
    }
}

Param
(
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $Location,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $ServicePrincipleName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $StorageAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $StorageAccountContainer,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $KeyVaultName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $CertificateSecretName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $CertificatePassword,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $CertificateFilePath,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $DockerUserName,
    [Parameter(Mandatory = $true, HelpMessage = "")]
    [string] $DockerUserPassword
)


# Assuming tenant is logged in already and selected the given subscription. 
New-ResourceGroup -ResourceGroupName $ResourceGroupName

# STORAGE ACCOUNT
# =============================================

# Create storage account
Write-Host "Creating storage account:" $StorageAccountName
$sa = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -Location $Location -SkuName Premium_LRS -EnableHttpsTrafficOnly 1

# Create container
Write-Host "Creating blob container:" $StorageAccountContainer
Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName | out-null
New-AzureStorageContainer -Name $StorageAccountContainer | out-null

Write-Host "=> Storage Account Resource ID:" $sa.Id

Write-Host "Assigning contributor role to" $ServicePrincipleName
New-AzureRMRoleAssignment -ApplicationId $ServicePrincipleName -RoleDefinitionName "Contributor" -Scope $sa.Id

# KEY VAULT
# =============================================

# Create key vault enabled for deployment
Write-Host "Creating key vault:" $KeyVaultName
$kv = New-AzureRmKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -Location $Location -Sku standard -EnabledForDeployment
Write-Host "=> Key Vault Resource ID:" $kv.ResourceId

Write-Host "Setting access polices for client" $ServicePrincipleName
Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $ServicePrincipleName -PermissionsToSecrets GET,LIST

# Store certificate as secret
Write-Host "Storing certificate in key vault:" $CertificateFilePath
$fileContentBytes = get-content $CertificateFilePath -Encoding Byte
$fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)
$jsonObject = @"
{
"data": "$filecontentencoded",
"dataType" :"pfx",
"password": "$CertificatePassword"
}
"@
$jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
$jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)
$secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText -Force
$kvSecret = Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $CertificateSecretName -SecretValue $secret -ContentType pfx

# Compute certificate thumbprint
Write-Host "Computing certificate thumbprint"
$tp = Get-PfxCertificate -FilePath $CertificateFilePath

Write-Host "=> Certificate URL:" $kvSecret.Id
Write-Host "=> Certificate thumbprint:" $tp.Thumbprint

Write-Host "Storing secret for sample user: $DockerUserName"
$userSecret = ConvertTo-SecureString -String $DockerUserPassword -AsPlainText -Force
Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $DockerUserName -SecretValue $userSecret -ContentType "user credentials" | out-null
