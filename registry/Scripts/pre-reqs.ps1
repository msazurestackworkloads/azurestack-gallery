$location = ""
$resourceGroup = ""
$saName = ""
$saContainer = ""
$kvName = ""
$pfxSecret = ""
$pfxPath = ""
$pfxPass = ""
$spnName = ""
$userName = ""
$userPass = ""


# RESOURCE GROUP
# =============================================

# Create resource group
Write-Host "Creating resource group:" $resourceGroup
New-AzureRmResourceGroup -Name $resourceGroup -Location $location | out-null


# STORAGE ACCOUNT
# =============================================

# Create storage account
Write-Host "Creating storage account:" $saName
$sa = New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -AccountName $saName -Location $location -SkuName Premium_LRS -EnableHttpsTrafficOnly 1

# Create container
Write-Host "Creating blob container:" $saContainer
Set-AzureRmCurrentStorageAccount -ResourceGroupName $resourceGroup -AccountName $saName | out-null
New-AzureStorageContainer -Name $saContainer | out-null

Write-Host "=> Storage Account Resource ID:" $sa.Id

Write-Host "Assigning contributor role to" $spnName
New-AzureRMRoleAssignment -ApplicationId $spnName -RoleDefinitionName "Contributor" -Scope $sa.Id

# KEY VAULT
# =============================================

# Create key vault enabled for deployment
Write-Host "Creating key vault:" $kvName
$kv = New-AzureRmKeyVault -ResourceGroupName $resourceGroup -VaultName $kvName -Location $location -Sku standard -EnabledForDeployment
Write-Host "=> Key Vault Resource ID:" $kv.ResourceId

Write-Host "Setting access polices for client" $spnName
Set-AzureRmKeyVaultAccessPolicy -VaultName $kvName -ServicePrincipalName $spnName -PermissionsToSecrets GET,LIST

# Store certificate as secret
Write-Host "Storing certificate in key vault:" $pfxPath
$fileContentBytes = get-content $pfxPath -Encoding Byte
$fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)
$jsonObject = @"
{
"data": "$filecontentencoded",
"dataType" :"pfx",
"password": "$pfxPass"
}
"@
$jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
$jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)
$secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText -Force
$kvSecret = Set-AzureKeyVaultSecret -VaultName $kvName -Name $pfxSecret -SecretValue $secret -ContentType pfx

# Compute certificate thumbprint
Write-Host "Computing certificate thumbprint"
$tp = Get-PfxCertificate -FilePath $pfxPath

Write-Host "=> Certificate URL:" $kvSecret.Id
Write-Host "=> Certificate thumbprint:" $tp.Thumbprint

Write-Host "Storing secret for sample user: $userName"
$userSecret = ConvertTo-SecureString -String $userPass -AsPlainText -Force
Set-AzureKeyVaultSecret -VaultName $kvName -Name $userName -SecretValue $userSecret -ContentType "user credential" | out-null
