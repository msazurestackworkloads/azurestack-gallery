

#######################################################################################################################
#######################################################################################################################
<#
.Synopsis
    Check if current user is logged in.

.Description
    Check if current user is logged in.
    Throws exption if user is not logged in.

.Example
   Get-AzureStackLoginStatus
#>
function Get-AzureStackLoginStatus ()
{
    $ErrorActionPreference = "SilentlyContinue";
    Get-AzureRmSubscription -ErrorVariable isTenantLoggedIn | Out-Null
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($isTenantLoggedIn)
    {
        throw "Login to ARM endpoint is not done. Please login, and select a given subscription."
    }
}

<#
.Synopsis
    Create a resource group under selected subscription
    
.Description
    Create a resource group under selected subscription
    It will skip creation of resource group if already present.

.Parameter ResourceGroupName
    Name of the resource group to be created.

.Example
   New-ResourceGroup -ResourceGroupName "resourcegroupname"
#>
function New-ResourceGroup (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the resource group to be created.")]
    [string] $ResourceGroupName
)
{
    Write-Host "Check if resource group ($ResourceGroupName) already exists" 
    $ErrorActionPreference = "SilentlyContinue";
    Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable resourceGroupExistError | Out-Null
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($resourceGroupExistError) {
        # Create resource group
        Write-Host "Resource group ($ResourceGroupName) does not exists. Creating a new resource group." 
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
        $ErrorActionPreference = "SilentlyContinue";
        Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable resourceGroupExistError
        $ErrorActionPreference = "Continue"; #Turning errors back on
        if ($resourceGroupExistError) {
            throw "Creation of resource group ($ResourceGroupName) failed."
        }

        Write-Host "Resource group ($ResourceGroupName) created successfully." 
    }
    else {        
        Write-Host "Resource group ($ResourceGroupName) already exists. Skipping creation."
    }
}

<#
.Synopsis
    Create a storage account under given resource group

.Description
    Create a storage account under given resource group
    It will skip creation of storage account resource if already present.
    Return storage account details.

.Parameter ResourceGroupName
    The storage account's resource group.

.Parameter Location
    Location of Azure Stack.

.Parameter StorageAccountName
    Storage account name which needs to be created.

.Parameter SkuName
    Storage account sku name to be used.

.Parameter EnableHttpsTrafficOnly
    Enable flag to have https traffic only.

.Example
   New-StorageAccount -ResourceGroupName "resourcegroupname"
                      -Location "local"
                      -StorageAccountName "storageaccountname"
                      -SkuName "Premium_LRS"
                      -EnableHttpsTrafficOnly 1
#>
function New-StorageAccount (
    [Parameter(Mandatory = $true, HelpMessage = "The storage account's resource group.")]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $true, HelpMessage = "Storage account name which needs to be created.")]
    [string] $StorageAccountName,
    [Parameter(Mandatory = $false, HelpMessage = "Storage account sku name to be used.")]
    [string] $SkuName = "Premium_LRS",
    [Parameter(Mandatory = $false, HelpMessage = "Enable flag to have https traffic only.")]
    [int] $EnableHttpsTrafficOnly = 1
)
{
    # Create storage account
    Write-Host "Check if storage account ($StorageAccountName) already exists"
    $ErrorActionPreference = "SilentlyContinue";
    $storageAccountDetails = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                                       -Name $StorageAccountName `
                                                       -ErrorVariable storageAccountExistError
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($storageAccountExistError) {
        Write-Host "Storage account does not exists. Creating a new storage account ($StorageAccountName) under resource group ($ResourceGroupName)." 
        $ErrorActionPreference = "SilentlyContinue";
        New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                  -AccountName $StorageAccountName `
                                  -Location $Location `
                                  -SkuName $SkuName `
                                  -EnableHttpsTrafficOnly $EnableHttpsTrafficOnly | Out-Null
        
        $storageAccountDetails = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                                           -Name $StorageAccountName `
                                                           -ErrorVariable storageAccountExistError
        $ErrorActionPreference = "Continue"; #Turning errors back on
        if ($storageAccountExistError) {
            throw "Creation a new storage account ($StorageAccountName) under resource group ($ResourceGroupName) failed. Check if specified storage account already exists under a subscription." 
        }
        Write-Host "Storage account ($StorageAccountName) created successfully." 
    }
    else {        
        Write-Host "Storage account ($StorageAccountName) already exists. Skipping creation."
    }

    return $storageAccountDetails
}

<#
.Synopsis
    Create a account blob container under given storage account

.Description
    Create a account blob container under given storage account
    It will skip creation of storage account blob container if already present.

.Parameter ResourceGroupName
    The storage account's resource group

.Parameter StorageAccountName
    Storage account name under which storage blob needs to be created.

.Parameter StorageAccountBlobContainer
    Storage account blob container name which needs to be created.

.Example
    New-StorageAccountContainer -ResourceGroupName "resourcegroupname"
                    -StorageAccountName "storageaccountname"
                    -StorageAccountBlobContainer "images"
#>
function New-StorageAccountContainer (
    [Parameter(Mandatory = $true, HelpMessage = "The storage account's resource group.")]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "Storage account name under which storage blob needs to be created.")]
    [string] $StorageAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "Storage account blob container name which needs to be created.")]
    [string] $StorageAccountBlobContainer
)
{
    # Storage Account Container
    # =============================================
    Write-Host "Check if storage account blob container ($StorageAccountBlobContainer) already exists."
    $ErrorActionPreference = "SilentlyContinue";
    Get-AzureStorageContainer -Name $StorageAccountBlobContainer -ErrorVariable storageContainerExistError | Out-Null
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($storageContainerExistError) {
        # Create container under storage account
        Write-Host "Blob container does not exists. Creating blob container ($StorageAccountBlobContainer) under storage account ($StorageAccountName)."
        New-AzureStorageContainer -Name $StorageAccountBlobContainer | Out-Null
        $ErrorActionPreference = "SilentlyContinue";
        Get-AzureStorageContainer -Name $StorageAccountBlobContainer -ErrorVariable storageContainerExistError | Out-Null
        $ErrorActionPreference = "Continue"; #Turning errors back on
        if ($storageContainerExistError) {
            throw "Creation of storage blob container ($StorageAccountBlobContainer) failed."
        }
    }
    else {        
        Write-Host "Storage blob container ($StorageAccountBlobContainer) already exists. Skipping creation."
    }
}

<#
.Synopsis
    Create a key vault account under given resource group

.Description
    Create a key vault account under given resource group
    It will skip creation of key vault if already present.
    Return key vault details.

.Parameter ResourceGroupName
    Name of the resource group under which key vault to be created.

.Parameter Location
    Location of Azure Stack.

.Parameter KeyVaultName
    Keyvault name which needs to be created.

.Parameter Sku
    Sku to be used to create keyVault. Default is standard.

.Example
   New-KeyVault -ResourceGroupName "resourcegroupname"
                -Location "local"
                -KeyVaultName "keyvault"
#>
function New-KeyVault (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the resource group under which key vault to be created.")]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $true, HelpMessage = "Keyvault name which needs to be created.")]
    [string] $KeyVaultName,
    [Parameter(Mandatory = $false, HelpMessage = "Sku to be used to create keyVault.")]
    [string] $Sku = "standard"
)
{
    Write-Host "Check if key vault($KeyVaultName) exists."
    $ErrorActionPreference = "SilentlyContinue";
    $keyVaultDetails = Get-AzureRmKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroupName 
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if (-not $keyVaultDetails)
    {
        Write-Host "Creating key vault ($KeyVaultName) as it does not exists."
        $ErrorActionPreference = "SilentlyContinue";
        $keyVaultDetails = New-AzureRmKeyVault -ResourceGroupName $ResourceGroupName `
                                               -VaultName $KeyVaultName `
                                               -Location $Location `
                                               -Sku $Sku `
                                               -EnabledForDeployment
        $ErrorActionPreference = "Continue"; #Turning errors back on
        if (-not $keyVaultDetails){
            throw "Creation of KeyVault ($KeyVaultName) failed."
        }
    }
    else {        
        Write-Host "Key vault ($KeyVaultName) already exists. Skipping creation."
    }

    return $keyVaultDetails
}

<#
.Synopsis
    Create a secret under given key vault.

.Description
    Create a secret under given key vault.
    It will throw error if already present. 
    Force update is allowed when SkipExistCheck value is true. 

.Parameter KeyVaultName
    Keyvault name under which secret needs to be created.

.Parameter SecretName
    Name of the secret.

.Parameter SecretValue
    Value which needs to be set for given secret name.

.Parameter ContentType
    Type of the content.

.Parameter SkipExistCheck
    Skip validation check and update if set to true. Default is false.
    
.Example
   New-KeyVaultSecret -KeyVaultName "keyvault"
                      -SecretName <Name of secret>
                      -SecretValue <Value of secret>
                      -ContentType <Description of the content>
                      -SkipExistCheck $true

#>
function New-KeyVaultSecret (
    [Parameter(Mandatory = $true, HelpMessage = "Keyvault name under which secret needs to be created.")]
    [string] $KeyVaultName,
    [Parameter(Mandatory = $true, HelpMessage = "Name of the secret.")]
    [string] $SecretName,
    [Parameter(Mandatory = $true, HelpMessage = "Value which needs to be set for given secret name.")]
    [string] $SecretValue,
    [Parameter(Mandatory = $true, HelpMessage = "Type of the content.")]
    [string] $ContentType,
    [Parameter(Mandatory = $false, HelpMessage = "Skip validation check and update if set to true.")]
    [bool] $SkipExistCheck = $false
)
{
    Write-Host "Check if key vault secret name ($SecretName) exists."
    $ErrorActionPreference = "SilentlyContinue";
    $keyVaultSecretDetails = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ((-not $keyVaultSecretDetails) -or $SkipExistCheck)
    {
        Write-Host "Creating key vault secret name ($SecretName) as it does not exists."
        $secureSecret = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
        Set-AzureKeyVaultSecret -VaultName $KeyVaultName `
                                -Name $SecretName `
                                -SecretValue $secureSecret `
                                -ContentType $ContentType | Out-Null
        $ErrorActionPreference = "SilentlyContinue";
        $keyVaultSecretDetails = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
        $ErrorActionPreference = "Continue"; #Turning errors back on
        if (-not $keyVaultSecretDetails){
            throw "Creation of key vault secret ($SecretName) failed. Check if the specified key vault already exists under a subscription."
        }
    }
    else {
        throw "Key vault with given secret name ($SecretName) already exists."
    }
}

<#
.Synopsis
    Read and convert certificate in Json enable format.

.Description
    Read and convert certificate in Json enable format.
    Returns json based certificate details which can then be added as secret to Key vault.

.Parameter CertificateFilePath
    Full file path where certificate file is present.

.Parameter CertificatePassword
    Password to read the certificate.

.Example
  Get-CertificateEncoded -CertificateFilePath "c:\certificate\cert.pfx" 
                         -CertificatePassword <Secret to read pfx file>

#>
function Get-CertificateEncoded (
    [Parameter(Mandatory = $true, HelpMessage = "Full file path where certificate file is present.")]
    [string] $CertificateFilePath,
    [Parameter(Mandatory = $true, HelpMessage = "Password to read the certificate.")]
    [string] $CertificatePassword
)
{
    # Store certificate as secret
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
    return $jsonEncoded
}


#######################################################################################################################
#######################################################################################################################

<#
.Synopsis
    Create or update existing cert secret under given key vault.

.Description
    Create or update existing cert secret under given key vault.
    Force update is allowed when SkipExistCheck value is true.

.Parameter KeyVaultName
    Keyvault name under which secret needs to be created.

.Parameter CertificateSecretName
    Secret name for the certificate which needs to be created in keyvault.

.Parameter CertificateFilePath
    Full file path where certificate file is present.

.Parameter CertificatePassword
    Password to read the certificate.

.Parameter SkipExistCheck
    Skip validation check and update if set to true. Default is false.
    
.Example
   Set-CertificateSecret -KeyVaultName "keyvault"
                         -CertificateSecretName <Name of secret>
                         -CertificateFilePath "c:\certificate\cert.pfx" 
                         -CertificatePassword <Secret to read pfx file>
                         -SkipExistCheck $true
#>
function Set-CertificateSecret (
    [Parameter(Mandatory = $true, HelpMessage = "Keyvault name which needs to be created.")]
    [string] $KeyVaultName,    
    [Parameter(Mandatory = $true, HelpMessage = "Secret name for the certificate which needs to be created in keyvault.")]
    [string] $CertificateSecretName,
    [Parameter(Mandatory = $true, HelpMessage = "Full file path where certificate file is present.")]
    [string] $CertificateFilePath,
    [Parameter(Mandatory = $true, HelpMessage = "Password to read the certificate.")]
    [string] $CertificatePassword,
    [Parameter(Mandatory = $false, HelpMessage = "Skip validation check and update if set to true.")]
    [bool] $SkipExistCheck = $false
)
{
    # Assuming tenant is logged in already and selected the given subscription.
    # best case check if tenant is loged in. Currently subscription selected status is not checked.
    Get-AzureStackLoginStatus
    # Store certificate as secret
    $secret = Get-CertificateEncoded -CertificateFilePath $CertificateFilePath `
                                     -CertificatePassword $CertificatePassword
    # Secret related to certificate.
    New-KeyVaultSecret -KeyVaultName $KeyVaultName `
                    -SecretName $CertificateSecretName `
                    -SecretValue $secret `
                    -ContentType pfx `
                    -SkipExistCheck $SkipExistCheck

    $keyVaultDetails = Get-AzureRmKeyVault -Name $KeyVaultName
    $keyVaultSecretDetails = Get-AzureKeyVaultSecret -VaultName $KeyVaultName `
                                                     -Name $CertificateSecretName
    
    $mypwd = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
    $pfxData = Get-PfxData -FilePath $CertificateFilePath -Password $mypwd

    Write-Host "----------------------------------------------------------------"
    Write-Host "PFX KeyVaultResourceId       : $($keyVaultDetails.ResourceId)"
    Write-Host "PFX KeyVaultSecretUrl        : $($keyVaultSecretDetails.Id)"
    Write-Host "PFX Certificate Thumbprint   : $($pfxData.EndEntityCertificates.Thumbprint)"
    Write-Host "----------------------------------------------------------------"
}

<#
.Synopsis
    Create or update existing secret under given key vault.

.Description
    Create or update existing secret under given key vault.
    Force update is allowed when SkipExistCheck value is true. 

.Parameter KeyVaultName
    Keyvault name under which secret needs to be created.

.Parameter RegistryUserName
    User name using which images will be push and pull.

.Parameter RegistryUserPassword
    Password using which images will be push and pull.

.Parameter SkipExistCheck
    Skip validation check and update if set to true. Default is false.
    
.Example
   Set-RegistryAccessSecret -KeyVaultName "keyvault"
                            -RegistryUserName <User name to access registry server>
                            -RegistryUserPassword <Password to access registry server>
                            -SkipExistCheck $true
#>
function Set-RegistryAccessSecret (
    [Parameter(Mandatory = $true, HelpMessage = "Keyvault name which needs to be created.")]
    [string] $KeyVaultName,    
    [Parameter(Mandatory = $true, HelpMessage = "User name using which images will be push and pull.")]
    [string] $RegistryUserName,
    [Parameter(Mandatory = $true, HelpMessage = "Password using which images will be push and pull.")]
    [string] $RegistryUserPassword,
    [Parameter(Mandatory = $false, HelpMessage = "Skip validation check and update if set to true.")]
    [bool] $SkipExistCheck = $false
)
{
    # Assuming tenant is logged in already and selected the given subscription.
    # best case check if tenant is loged in. Currently subscription selected status is not checked.
    Get-AzureStackLoginStatus
    New-KeyVaultSecret -KeyVaultName $KeyVaultName `
                    -SecretName $RegistryUserName `
                    -SecretValue $RegistryUserPassword `
                    -ContentType "user credentials" `
                    -SkipExistCheck $SkipExistCheck
}

<#
.Synopsis
    Create all the pre-requisite required for container registry.

.Description
    Create all the pre-requisite required for container registry.

.Parameter Location
    Location of Azure Stack.

.Parameter ServicePrincipleId
    Service principle ID which will be added to provide contributor access

.Parameter ResourceGroupName
    Name of the resource group to be created.

.Parameter StorageAccountName
   Storage account name which needs to be created.

.Parameter StorageAccountBlobContainer
    Storage account blob container name which needs to be created.

.Parameter KeyVaultName
    Keyvault name which needs to be created.

.Parameter CertificateSecretName
    Secret name for the certificate which needs to be created in keyvault.

.Parameter CertificateFilePath
    Full file path where certificate file is present.

.Parameter CertificatePassword
   Password to read the certificate.

.Parameter RegistryUserName
    User name using which images will be push and pull.

.Parameter RegistryUserPassword
    Password using which images will be push and pull.

.Example
  Set-ContainerRegistryPrerequisites

#>
function Set-ContainerRegistryPrerequisites
(
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $true, HelpMessage = "Service principle ID which will be added to provide contributor access.")]
    [string] $ServicePrincipleId,
    [Parameter(Mandatory = $true, HelpMessage = "Name of the resource group to be created.")]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "Storage account name which needs to be created.")]
    [string] $StorageAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "Storage account blob container name which needs to be created.")]
    [string] $StorageAccountBlobContainer,
    [Parameter(Mandatory = $true, HelpMessage = "Keyvault name which needs to be created.")]
    [string] $KeyVaultName,    
    [Parameter(Mandatory = $true, HelpMessage = "Secret name for the certificate which needs to be created in keyvault.")]
    [string] $CertificateSecretName,
    [Parameter(Mandatory = $true, HelpMessage = "Full file path where certificate file is present.")]
    [string] $CertificateFilePath,
    [Parameter(Mandatory = $true, HelpMessage = "Password to read the certificate.")]
    [string] $CertificatePassword, 
    [Parameter(Mandatory = $true, HelpMessage = "User name using which images will be push and pull.")]
    [string] $RegistryUserName,
    [Parameter(Mandatory = $true, HelpMessage = "Password using which images will be push and pull.")]
    [string] $RegistryUserPassword
)
{
    # Assuming tenant is logged in already and selected the given subscription.
    # best case check if tenant is loged in. Currently subscription selected status is not checked.
    Get-AzureStackLoginStatus

    # Create resource group. In case exists skip creation.
    New-ResourceGroup -ResourceGroupName $ResourceGroupName

    # Create storage account. In case exists skip creation.
    $storageAccountDetails = New-StorageAccount -ResourceGroupName $ResourceGroupName `
                                    -Location $Location `
                                    -StorageAccountName $StorageAccountName

    # Create current context to given storage account.
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroupName `
                                     -AccountName $StorageAccountName | out-null

    # Create new storage blob container.
    New-StorageAccountContainer -ResourceGroupName $ResourceGroupName `
                                -StorageAccountName $StorageAccountName `
                                -StorageAccountBlobContainer $StorageAccountBlobContainer

    Write-Host "Checking if ServicePrincipleId ($ServicePrincipleId) already has access on storage account ($StorageAccountName), ."
    $ErrorActionPreference = "SilentlyContinue";
    Get-AzureRMRoleAssignment -ServicePrincipalName $ServicePrincipleId `
                              -Scope $storageAccountDetails.Id `
                              -ErrorVariable accessExistError | Out-Null
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($accessExistError) {
        Write-Host "Assigning servicePrincipleId ($ServicePrincipleId) contributor role on storage account ($StorageAccountName)"
        New-AzureRMRoleAssignment -ApplicationId $ServicePrincipleId `
                                  -RoleDefinitionName "Contributor" `
                                  -Scope $storageAccountDetails.Id
    }
    else {
        Write-Host "ServicePrincipleId ($ServicePrincipleId) already has access on Storage account ($StorageAccountName) "
    }

    # Create key vault enabled for deployment
    New-KeyVault -ResourceGroupName $ResourceGroupName `
                 -Location $Location `
                 -KeyVaultName $KeyVaultName `
                 -Sku standard | Out-Null
    Write-Host "Set access policy on keyvault ($KeyVaultName) for client ($ServicePrincipleId)" 
    Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName `
                                    -ServicePrincipalName $ServicePrincipleId `
                                    -PermissionsToSecrets GET,LIST

    # Secret related to registry credentials.
    Set-RegistryAccessSecret -KeyVaultName $KeyVaultName `
                             -RegistryUserName $RegistryUserName `
                             -RegistryUserPassword $RegistryUserPassword `
                             -SkipExistCheck $true

    # Store certificate as secret
    Set-CertificateSecret -KeyVaultName $KeyVaultName `
                          -CertificateSecretName $CertificateSecretName `
                          -CertificateFilePath $CertificateFilePath `
                          -CertificatePassword $CertificatePassword `
                          -SkipExistCheck $true

    Write-Host "StorageAccountResourceId     : $($storageAccountDetails.Id)"
    Write-Host "Blob Container               : $StorageAccountBlobContainer"
    Write-Host "----------------------------------------------------------------"
    Get-VMImageSku -Location $Location
    Write-Host "----------------------------------------------------------------"
}

<#
.Synopsis
    Returns set of SKUs available for given publisher and offer.

.Description
    Returns set of SKUs available for given publisher and offer.

.Parameter Location
    Location where Azure Stack is deployed.

.Parameter PublisherName
    Publisher name of given image. Default value is microsoft-aks.

.Parameter Offer
    Offer name of given image. Default value is aks.

.Example
   Get-VMImageSku -Location local
#>
function Get-VMImageSku (
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $false, HelpMessage = "Publisher name of given image.")]
    [string] $PublisherName = "microsoft-aks",
    [Parameter(Mandatory = $false, HelpMessage = "Offer name of given image.")]
    [string] $Offer = "aks"
)
{
    # Assuming tenant is logged in already and selected the given subscription.
    # best case check if tenant is loged in. Currently subscription selected status is not checked.
    Get-AzureStackLoginStatus

    $ErrorActionPreference = "SilentlyContinue";
    $skuDetails = Get-AzureRmVMImageSku -Location $Location -PublisherName $PublisherName -Offer $Offer
    $ErrorActionPreference = "Continue"; #Turning errors back on
    if ($skuDetails) {
        Write-Host "Available Skus:"
        $skuDetails | ForEach-Object {
            '{0}' -f $_.Skus
          }
        #$skuDetails | Select-Object Skus
    }
    else {
        Write-Host "No image sku found with publisher ($PublisherName) and offer ($Offer)."
    }
}