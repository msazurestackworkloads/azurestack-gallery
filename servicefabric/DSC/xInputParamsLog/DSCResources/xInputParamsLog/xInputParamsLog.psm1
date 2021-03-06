function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
    [Parameter(Mandatory = $true)]
    [Int] $DeploymentNodeIndex,

    [Parameter(Mandatory = $true)]
    [string] $ClusterName,

    [Parameter(Mandatory = $true)]
    [string] $VMNodeTypePrefix,

    [Parameter(Mandatory = $true)]
    [Int[]] $VMNodeTypeInstanceCounts,

    [Parameter(Mandatory = $true)]
    [Int] $CurrentVMNodeTypeIndex,

    [parameter(Mandatory = $true)]
    [string] $SubnetIPFormat,

    [Parameter(Mandatory = $true)]
    [string] $clientConnectionEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $httpGatewayEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $reverseProxyEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralStartPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralEndPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationStartPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationEndPort,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricUrl,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricRuntimeUrl,

    [Parameter(Mandatory = $true)]
    [string] $certificateStoreValue,

    [Parameter(Mandatory = $true)]
    [string] $AdminUserName,

    [Parameter(Mandatory = $true)]
    [string] $ClusterCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ServerCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ReverseProxyCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $AdminClientCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $NonAdminClientCertificateCommonName,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityCertCommonName,

    [parameter(Mandatory = $false)]
    [System.String[]] $AdditionalCertCommonNamesNeedNetworkAccess = @(),
    
    [Parameter(Mandatory = $false)]
    [string] $ClusterCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $ServerCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $ReverseProxyCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $AdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $NonAdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $RootCACertBase64,

    [Parameter(Mandatory = $true)]
    [string] $DNSService,

    [Parameter(Mandatory = $true)]
    [string] $RepairManager,

    [Parameter(Mandatory = $true)]
    [string] $BackupRestoreService,

    [Parameter(Mandatory = $true)]
    [string] $ClientConnectionEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityApplicationId,

    [Parameter(Mandatory = $false)]
    [string] $ArmEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultDnsSuffix,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultServiceEndpointResourceId,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityTenantId,

    [Parameter(Mandatory = $false)]
    [string] $DSCAgentConfig,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionName,

    [Parameter(Mandatory = $true)]
    [bool] $StandaloneDeployment,

    [parameter(Mandatory = $false)]
    [System.Boolean]
    $DisableContainers,

    [parameter(Mandatory = $false)]
    [System.Boolean]
    $BRSDisableKVAuthorityValidation,

    [Parameter(Mandatory = $true)]
    [string] $ConfigurationMode,

    [Parameter(Mandatory = $true)]
    [string] $CurrentVersion
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $CommandName = $PSCmdlet.MyInvocation.InvocationName;
    $ParameterList = (Get-Command -Name $CommandName).Parameters;

    return $ParameterList
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
    [Parameter(Mandatory = $true)]
    [Int] $DeploymentNodeIndex,

    [Parameter(Mandatory = $true)]
    [string] $ClusterName,

    [Parameter(Mandatory = $true)]
    [string] $VMNodeTypePrefix,

    [Parameter(Mandatory = $true)]
    [Int[]] $VMNodeTypeInstanceCounts,

    [Parameter(Mandatory = $true)]
    [Int] $CurrentVMNodeTypeIndex,

    [parameter(Mandatory = $true)]
    [string] $SubnetIPFormat,

    [Parameter(Mandatory = $true)]
    [string] $clientConnectionEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $httpGatewayEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $reverseProxyEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralStartPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralEndPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationStartPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationEndPort,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricUrl,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricRuntimeUrl,

    [Parameter(Mandatory = $true)]
    [string] $certificateStoreValue,

    [Parameter(Mandatory = $true)]
    [string] $AdminUserName,

    [Parameter(Mandatory = $true)]
    [string] $ClusterCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ServerCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ReverseProxyCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $AdminClientCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $NonAdminClientCertificateCommonName,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityCertCommonName,

    [parameter(Mandatory = $false)]
    [System.String[]] $AdditionalCertCommonNamesNeedNetworkAccess = @(),

    [Parameter(Mandatory = $false)]
    [string] $ClusterCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $ServerCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $ReverseProxyCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $AdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $NonAdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $RootCACertBase64,

    [Parameter(Mandatory = $true)]
    [string] $DNSService,

    [Parameter(Mandatory = $true)]
    [string] $RepairManager,

    [Parameter(Mandatory = $true)]
    [string] $BackupRestoreService,

    [Parameter(Mandatory = $true)]
    [string] $ClientConnectionEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityApplicationId,

    [Parameter(Mandatory = $false)]
    [string] $ArmEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultDnsSuffix,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultServiceEndpointResourceId,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityTenantId,

    [Parameter(Mandatory = $false)]
    [string] $DSCAgentConfig,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionName,

    [Parameter(Mandatory = $true)]
    [bool] $StandaloneDeployment,

    [parameter(Mandatory = $false)]
    [System.Boolean]
    $DisableContainers,
    
    [parameter(Mandatory = $false)]
    [System.Boolean]
    $BRSDisableKVAuthorityValidation,

    [Parameter(Mandatory = $true)]
    [string] $ConfigurationMode,

    [Parameter(Mandatory = $true)]
    [string] $CurrentVersion
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $CommandName = $PSCmdlet.MyInvocation.InvocationName;
    $ParameterList = (Get-Command -Name $CommandName).Parameters;

    Write-Host "------------------------ INPUT PARAMETERS ------------------------"
    $ParameterList.GetEnumerator() | % { $v = Get-Variable -Name $_.Value.Name -ErrorAction SilentlyContinue; if ($v.Name -and $v.Name -notlike "*Thumbprint") { Write-Host "$($v.Name) - $($v.Value)" -Verbose } }
    Write-Host "------------------------ INPUT PARAMETERS END ------------------------"
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
    [Parameter(Mandatory = $true)]
    [Int] $DeploymentNodeIndex,

    [Parameter(Mandatory = $true)]
    [string] $ClusterName,

    [Parameter(Mandatory = $true)]
    [string] $VMNodeTypePrefix,

    [Parameter(Mandatory = $true)]
    [Int[]] $VMNodeTypeInstanceCounts,

    [Parameter(Mandatory = $true)]
    [Int] $CurrentVMNodeTypeIndex,

    [parameter(Mandatory = $true)]
    [string] $SubnetIPFormat,

    [Parameter(Mandatory = $true)]
    [string] $clientConnectionEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $httpGatewayEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $reverseProxyEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralStartPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralEndPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationStartPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationEndPort,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricUrl,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricRuntimeUrl,

    [Parameter(Mandatory = $true)]
    [string] $certificateStoreValue,

    [Parameter(Mandatory = $true)]
    [string] $AdminUserName,

    [Parameter(Mandatory = $true)]
    [string] $ClusterCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ServerCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $ReverseProxyCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $AdminClientCertificateCommonName,

    [Parameter(Mandatory = $true)]
    [string] $NonAdminClientCertificateCommonName,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityCertCommonName,

    [parameter(Mandatory = $false)]
    [System.String[]] $AdditionalCertCommonNamesNeedNetworkAccess = @(),

    [Parameter(Mandatory = $false)]
    [string] $ClusterCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $ServerCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $ReverseProxyCertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $AdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string[]] $NonAdminClientCertificateThumbprint = @(),

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string] $RootCACertBase64,

    [Parameter(Mandatory = $true)]
    [string] $DNSService,

    [Parameter(Mandatory = $true)]
    [string] $RepairManager,

    [Parameter(Mandatory = $true)]
    [string] $BackupRestoreService,

    [Parameter(Mandatory = $true)]
    [string] $ClientConnectionEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityApplicationId,

    [Parameter(Mandatory = $false)]
    [string] $ArmEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultDnsSuffix,

    [Parameter(Mandatory = $false)]
    [string] $AzureKeyVaultServiceEndpointResourceId,

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityTenantId,

    [Parameter(Mandatory = $false)]
    [string] $DSCAgentConfig,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionName,

    [Parameter(Mandatory = $true)]
    [bool] $StandaloneDeployment,

    [parameter(Mandatory = $false)]
    [System.Boolean]
    $DisableContainers,
    
    [parameter(Mandatory = $false)]
    [System.Boolean]
    $BRSDisableKVAuthorityValidation,

    [Parameter(Mandatory = $true)]
    [string] $ConfigurationMode,

    [Parameter(Mandatory = $true)]
    [string] $CurrentVersion
    )

    return $false
}

Export-ModuleMember -Function *-TargetResource