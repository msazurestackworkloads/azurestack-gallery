
function Get-AzureStackLoginStatus ()
{
    Get-AzureRmSubscription -ErrorVariable isTenantLogin
    if ($isTenantLogin)
    {
        throw "Tenant login is not done. Please login and select a given subscription"
    }
}

function Get-VMImageSku (
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $false, HelpMessage = "")]
    [string] $PublisherName = "microsoft-aks",
    [Parameter(Mandatory = $false, HelpMessage = "")]
    [string] $Offer = "aks"
)
{
    Get-AzureRmVMImageSku -Location $Location -PublisherName $PublisherName -Offer $Offer | Select-Object Skus
}

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
    Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable resourceGroupExistError | Out-Null
    if ($resourceGroupExistError) {
        # Create resource group
        Write-Host "Resource group ($ResourceGroupName) does not exist. Creating a new resource group." 
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
        Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable resourceGroupExistError
        if ($resourceGroupExistError) {
            throw "Creation of resource group($ResourceGroupName) failed."
        }
    }
}

<#
.Synopsis
    Create a storage account under given resource group

.Description
    Create a storage account under given resource group

.Parameter ResourceGroupName
    Resource group name under which storage account needs to be created.

.Parameter Location
    Azure Stack Location.

.Parameter StorageAccountName
    Storage account name which needs to be created.

.Parameter SkuName
    Storage account SKU to be used.

.Parameter EnableHttpsTrafficOnly
    Enable to have https traffic only.

.Example
   New-StorageAccount -ResourceGroupName "resourcegroupname"
                      -Location "local"
                      -StorageAccountName "storageaccountname"
                      -SkuName "Premium_LRS"
                      -EnableHttpsTrafficOnly 1
#>
function New-StorageAccount (
    [string] $ResourceGroupName,
    [string] $Location,
    [string] $StorageAccountName,
    [string] $SkuName = "Premium_LRS",
    [int] $EnableHttpsTrafficOnly = 1
)
{
    # Create storage account
    Write-Host "Check if storage account($StorageAccountName) already exist" 
    $storageAccountDetails = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                                       -Name $StorageAccountName `
                                                       -ErrorVariable storageAccountExistError | Out-Null
    if ($storageAccountExistError) {
        Write-Host "Storage account does not exist."
        Write-Host "Creating a new storage account($StorageAccountName) under resource group($ResourceGroupName)." 
        New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                  -AccountName $StorageAccountName `
                                  -Location $Location `
                                  -SkuName $SkuName `
                                  -EnableHttpsTrafficOnly $EnableHttpsTrafficOnly
        $storageAccountDetails = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                                           -Name $StorageAccountName `
                                                           -ErrorVariable storageAccountExistError | Out-Null
        if ($storageAccountExistError) {
            throw "Creation a new storage account($StorageAccountName) under resource group($ResourceGroupName) failed." 
        }
    }

    return $storageAccountDetails
}

<#
.Synopsis
    Create a account blob container under given storage account

.Description
    Create a account blob container under given storage account

.Parameter ResourceGroupName
    Resource group name under which storage account needs to be created.

.Parameter StorageAccountName
    Storage account name under which storage account needs to be created.

.Parameter StorageAccountBlobContainer
    Storage account blob container name which needs to be created.

.Example
   New-ResourceGroup -ResourceGroupName "resourcegroupname"
#>
function New-StorageAccountContainer (
    [string] $ResourceGroupName,
    [string] $StorageAccountName,
    [string] $StorageAccountBlobContainer
)
{
    # Storage Account Container
    # =============================================
    Write-Host "Check if storage account blob container($StorageAccountContainer) already exist." 
    Get-AzureStorageContainer -Name $StorageAccountContainer -ErrorVariable storageContainerExistError | Out-Null
    if ($storageContainerExistError) {
        # Create container under storage account
        Write-Host "Creating blob container($StorageAccountContainer) under stroage account($StorageAccountName)." 
        New-AzureStorageContainer -Name $StorageAccountContainer | out-null
        Get-AzureStorageContainer -Name $StorageAccountContainer -ErrorVariable storageContainerExistError | Out-Null
        if ($storageContainerExistError) {
            throw "Creation of storage blob container($StorageAccountContainer) failed."
        }
    }
}

function New-KeyVault (
    [string] $ResourceGroupName,
    [string] $Location,
    [string] $KeyVaultName,
    [string] $Sku = "standard"
)
{
    Write-Host "Check if key vault($KeyVaultName) exist." 
    $keyVaultDetails = Get-AzureRmKeyVault -Name $KeyVaultName
    if (-not $keyVaultDetails)
    {
        Write-Host "Creating key vault($KeyVaultName) as it does not exist."
        $keyVaultDetails = New-AzureRmKeyVault -ResourceGroupName $ResourceGroupName `
                                               -VaultName $KeyVaultName `
                                               -Location $Location `
                                               -Sku $Sku `
                                               -EnabledForDeployment
    }

    return $keyVaultDetails
}


function New-KeyVaultSecret (
    [string] $KeyVaultName,
    [string] $SecretName,
    [string] $SecretValue,
    [string] $ContentType
)
{
    Write-Host "Check if key vault secret name ($SecretName) exist." 
    $keyVaultSecretDetails = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
    if (-not $keyVaultSecretDetails)
    {
        Write-Host "Creating key vault secret name ($SecretName) as it does not exist."
        $secureSecret = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
        Set-AzureKeyVaultSecret -VaultName $KeyVaultName `
                                -Name $SecretName `
                                -SecretValue $secureSecret `
                                -ContentType $ContentType
    }
    else {
        throw "Key vault secret name already exist. "
    }
}


function Get-CertificateEncoded (
    [string] $CertificateFilePath,
    [string] $CertificateSecret
)
{
    # Store certificate as secret
    $fileContentBytes = get-content $CertificateFilePath -Encoding Byte
    $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)
    $jsonObject = @"
    {
    "data": "$filecontentencoded",
    "dataType" :"pfx",
    "password": "$CertificateSecret"
    }
"@
    $jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
    $jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)
    return $jsonEncoded
}

function New-ContainerRegistryPrerequisite
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
    [string] $StorageAccountBlobContainer,
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
{
    # Assuming tenant is logged in already and selected the given subscription. 

    # Create resource group. In case exist skip creation.
    New-ResourceGroup -ResourceGroupName $ResourceGroupName

    # Create storage account. In case exist skip creation.
    $storageAccountDetails = New-StorageAccount -ResourceGroupName $ResourceGroupName `
                                    -Location $Location `
                                    -StorageAccountName $StorageAccountName

    # Create current context to given storage account.
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName | out-null

    # Create new storage blob container.
    New-StorageAccountContainer -ResourceGroupName $ResourceGroupName `
                                -StorageAccountName $StorageAccountName `
                                -StorageAccountBlobContainer $StorageAccountBlobContainer

    # Todo need to check how to make it idempotent
    Write-Host "Assigning contributor role to $ServicePrincipleName on $StorageAccountName"
    New-AzureRMRoleAssignment -ApplicationId $ServicePrincipleName -RoleDefinitionName "Contributor" -Scope $storageAccountDetails.Id

    # Create key vault enabled for deployment
    $keyVaultDetails = New-KeyVault -ResourceGroupName $ResourceGroupName -Location $Location -KeyVaultName $KeyVaultName -Sku standard

    # Todo need to check how to make it idempotent
    Write-Host "Setting access polices for client" $ServicePrincipleName
    Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $ServicePrincipleName -PermissionsToSecrets GET,LIST

    # Store certificate as secret

    $secret = Get-CertificateEncoded -CertificateFilePath $CertificateFilePath -CertificateSecret $CertificatePassword

    # Secret related to certificate.
    New-KeyVaultSecret -KeyVaultName $KeyVaultName `
                    -SecretName $CertificateSecretName `
                    -SecretValue $secret `
                    -ContentType pfx

    # Secret related to docker credentials.
    New-KeyVaultSecret -KeyVaultName $KeyVaultName `
                    -SecretName $DockerUserName `
                    -SecretValue $DockerUserPassword `
                    -ContentType "user credentials"

    #Write-Host "=> Storage Account Resource ID:" $storageAccountDetails.Id
    # Compute certificate thumbprint
    #Write-Host "Computing certificate thumbprint"
    #$tp = Get-PfxCertificate -FilePath $CertificateFilePath
    #Write-Host "=> Certificate URL:" $kvSecret.Id
    #Write-Host "=> Certificate thumbprint:" $tp.Thumbprint
}