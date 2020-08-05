Configuration InstallServiceFabricConfiguration
{
    param
    (
    [Parameter(Mandatory = $false)]
    [Int] $DeploymentNodeIndex = 0,

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
    [PSCredential] $Credential,

    [Parameter(Mandatory = $true)]
    [string] $CertificateStoreValue,

    [Parameter(Mandatory = $true)]
    [string] $AdminUserName,

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

    [Parameter(Mandatory = $false)]
    [ValidateSet('Yes','No')]
    [string] $DNSService = "No",

    [Parameter(Mandatory = $false)]
    [ValidateSet('Yes','No')]
    [string] $RepairManager = "No",

    [Parameter(Mandatory = $false)]
    [ValidateSet('Yes','No')]
    [string] $BackupRestoreService = "No",

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

    [Parameter(Mandatory = $false)]
    [string] $ClusterCertificateCommonName = "SFClusterCertificate",

    [Parameter(Mandatory = $false)]
    [string] $ServerCertificateCommonName = "SFServerCertificate",

    [Parameter(Mandatory = $false)]
    [string] $ReverseProxyCertificateCommonName = "SFReverseProxyCertificate",

    [Parameter(Mandatory = $false)]
    [string] $AdminClientCertificateCommonName = "SFAdminClientCertificate",

    [Parameter(Mandatory = $false)]
    [string] $NonAdminClientCertificateCommonName = "SFNonAdminClientCertificate",

    [Parameter(Mandatory = $false)]
    [string] $ProviderIdentityCertCommonName,

    [parameter(Mandatory = $false)]
    [System.String[]] $AdditionalCertCommonNamesNeedNetworkAccess = @(),

    # Indicates whether the DSC Agent (InstallServiceFabricCertificates) resource exists or not.
    # This parameter is added for consistency DSC resources for Standalone and Addon-RP deployments
    [Parameter(Mandatory = $false)]
    [bool] $StandaloneDeployment = $true,

    [Parameter(Mandatory = $false)]
    [bool] $DisableStrongNameValidation,

    [Parameter(Mandatory = $false)]
    [bool] $BRSDisableKVAuthorityValidation,

    [Parameter(Mandatory = $false)]
    [bool] $DisableContainers,

    # Configuration mode for DSC
    [ValidateSet('ApplyOnly','ApplyAndMonitor','ApplyAndAutoCorrect')]
    [string] $ConfigurationMode = "ApplyOnly",

    # Do not change the var, it is placeholder replacing during build time.
    [string] $CurrentVersion = "1.2005.71.4"
    )

    # Install Common utils Module
    $ModuleFilePath="$PSScriptRoot\xSfClusterDSC.Common.psm1"
    $ModuleName = "xSfClusterDSC.Common"
    $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
    $ModuleFolder = "$PSModulePath\$ModuleName"
    if (-not (Test-Path  $ModuleFolder -PathType Container)) { mkdir $ModuleFolder }

    Copy-Item $ModuleFilePath $ModuleFolder -Force

    Import-DscResource -ModuleName PSDesiredStateConfiguration,`
                    xInputParamsLog,`
                    xDisk,`
                    xSfCertificatesPermit,`
                    xHKLMSettings,`
                    xFirewallConfigure,`
                    xPackagesDownload,`
                    xSfClusterCreateOps,`
                    xSfClusterNodesOps,`
                    xLocalPolicySettings


    Node localhost {

        xInputParamsLog LogInputParams
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            ClusterName = $ClusterName
            VMNodeTypePrefix = $VMNodeTypePrefix
            VMNodeTypeInstanceCounts=$VMNodeTypeInstanceCounts
            CurrentVMNodeTypeIndex=$CurrentVMNodeTypeIndex
            SubnetIPFormat=$SubnetIPFormat
            ClientConnectionEndpointPort = $clientConnectionEndpointPort
            HTTPGatewayEndpointPort = $httpGatewayEndpointPort
            ReverseProxyEndpointPort = $reverseProxyEndpointPort
            EphemeralStartPort = $ephemeralStartPort
            EphemeralEndPort = $ephemeralEndPort
            ApplicationStartPort = $applicationStartPort
            ApplicationEndPort = $applicationEndPort
            ConfigPath = $ConfigPath
            ServiceFabricUrl = $ServiceFabricUrl
            ServiceFabricRuntimeUrl = $ServiceFabricRuntimeUrl
            CertificateStoreValue = $CertificateStoreValue
            AdminUserName = $AdminUserName
            ClusterCertificateCommonName = $ClusterCertificateCommonName
            ServerCertificateCommonName = $ServerCertificateCommonName
            ReverseProxyCertificateCommonName = $ReverseProxyCertificateCommonName
            AdminClientCertificateCommonName = $AdminClientCertificateCommonName
            NonAdminClientCertificateCommonName = $NonAdminClientCertificateCommonName
            ProviderIdentityCertCommonName = $ProviderIdentityCertCommonName
            AdditionalCertCommonNamesNeedNetworkAccess = $AdditionalCertCommonNamesNeedNetworkAccess
            ClusterCertificateThumbprint = $ClusterCertificateThumbprint
            ServerCertificateThumbprint = $ServerCertificateThumbprint
            ReverseProxyCertificateThumbprint = $ReverseProxyCertificateThumbprint
            AdminClientCertificateThumbprint = $AdminClientCertificateThumbprint
            NonAdminClientCertificateThumbprint = $NonAdminClientCertificateThumbprint
            ClientConnectionEndpoint = $ClientConnectionEndpoint
            RootCACertBase64 = $RootCACertBase64
            DNSService = $DNSService
            RepairManager = $RepairManager
            BackupRestoreService = $BackupRestoreService
            ProviderIdentityApplicationId = $ProviderIdentityApplicationId
            ArmEndpoint = $ArmEndpoint
            AzureKeyVaultDnsSuffix = $AzureKeyVaultDnsSuffix
            AzureKeyVaultServiceEndpointResourceId = $AzureKeyVaultServiceEndpointResourceId
            ProviderIdentityTenantId = $ProviderIdentityTenantId
            DSCAgentConfig = $DSCAgentConfig
            SubscriptionName = $SubscriptionName
            DisableContainers = $DisableContainers
            StandaloneDeployment = $StandaloneDeployment
            ConfigurationMode = $ConfigurationMode
            CurrentVersion = $CurrentVersion
            BRSDisableKVAuthorityValidation = $BRSDisableKVAuthorityValidation
        }

        xWaitforDisk AddDisk
        {
            DiskNumber = 2
            RetryIntervalSec = 30
            RetryCount = 10
            DependsOn = '[xInputParamsLog]LogInputParams'
        }

        xDisk DataDisk
        {
            DiskNumber = 2
            DriveLetter = "E"
            DependsOn = '[xWaitforDisk]AddDisk'
        }

        xLocalPolicySettings ConfigureLocalPolicies
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            DependsOn = '[xDisk]DataDisk'
        }

        xFirewallConfigure ConfigureFirewall 
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            VMNodeTypeInstanceCounts=$VMNodeTypeInstanceCounts
            SubnetIPFormat=$SubnetIPFormat
            ClientConnectionEndpointPort = $clientConnectionEndpointPort
            ClientConnectionEndpoint = $ClientConnectionEndpoint
            ClusterCertificateCommonName = $ClusterCertificateCommonName
            ServerCertificateCommonName = $ServerCertificateCommonName
            ClusterCertificateThumbprint = $ClusterCertificateThumbprint
            ServerCertificateThumbprint = $ServerCertificateThumbprint
            DependsOn = '[xLocalPolicySettings]ConfigureLocalPolicies'
        }

        xHKLMSettings HKLMSettingsConfigure
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            DisableStrongNameValidation = $DisableStrongNameValidation
            DependsOn = '[xFirewallConfigure]ConfigureFirewall'
        }

        xPackagesDownload DownloadPackages 
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            ServiceFabricUrl = $serviceFabricUrl
            ServiceFabricRuntimeUrl = $serviceFabricRuntimeUrl
            DependsOn = '[xHKLMSettings]HKLMSettingsConfigure'
        }

        xSfCertificatesPermit ServiceFabricCertificatesPermissions
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            VMNodeTypePrefix = $VMNodeTypePrefix
            VMNodeTypeInstanceCounts=$VMNodeTypeInstanceCounts
            RootCACertBase64 = $RootCACertBase64
            AdminUserName = $AdminUserName
            ClusterCertificateCommonName = $ClusterCertificateCommonName
            ServerCertificateCommonName = $ServerCertificateCommonName
            ReverseProxyCertificateCommonName = $ReverseProxyCertificateCommonName
            AdditionalCertCommonNamesNeedNetworkAccess = $AdditionalCertCommonNamesNeedNetworkAccess
            ClusterCertificateThumbprint = $ClusterCertificateThumbprint
            ServerCertificateThumbprint = $ServerCertificateThumbprint
            ReverseProxyCertificateThumbprint = $ReverseProxyCertificaeThumbprint
            StandaloneDeployment = $StandaloneDeployment
            ProviderIdentityApplicationId = $ProviderIdentityApplicationId
            ArmEndpoint = $ArmEndpoint
            AzureKeyVaultDnsSuffix = $AzureKeyVaultDnsSuffix
            AzureKeyVaultServiceEndpointResourceId = $AzureKeyVaultServiceEndpointResourceId
            ProviderIdentityTenantId = $ProviderIdentityTenantId
            ProviderIdentityCertCommonName = $ProviderIdentityCertCommonName
            SubscriptionName = $SubscriptionName
            DSCAgentConfig = $DSCAgentConfig
            PsDscRunAsCredential = $Credential
            DependsOn = '[xPackagesDownload]DownloadPackages'
        }

        xSfClusterCreateOps CreateServiceFabricCluster
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            ClusterName = $ClusterName
            VMNodeTypePrefix = $VMNodeTypePrefix
            VMNodeTypeInstanceCounts=$VMNodeTypeInstanceCounts
            CurrentVMNodeTypeIndex=$CurrentVMNodeTypeIndex
            SubnetIPFormat=$SubnetIPFormat
            ClientConnectionEndpointPort = $clientConnectionEndpointPort
            HTTPGatewayEndpointPort = $httpGatewayEndpointPort
            ReverseProxyEndpointPort = $reverseProxyEndpointPort
            EphemeralStartPort = $ephemeralStartPort
            EphemeralEndPort = $ephemeralEndPort
            ApplicationStartPort = $applicationStartPort
            ApplicationEndPort = $applicationEndPort
            ConfigPath = $ConfigPath
            CertificateStoreValue = $CertificateStoreValue
            ClientConnectionEndpoint = $ClientConnectionEndpoint
            DNSService = $DNSService
            RepairManager = $RepairManager
            BackupRestoreService = $BackupRestoreService
            AdminUserName = $AdminUserName
            ClusterCertificateCommonName = $ClusterCertificateCommonName
            ServerCertificateCommonName = $ServerCertificateCommonName
            ReverseProxyCertificateCommonName = $ReverseProxyCertificateCommonName
            AdminClientCertificateCommonName = $AdminClientCertificateCommonName
            NonAdminClientCertificateCommonName = $NonAdminClientCertificateCommonName
            ClusterCertificateThumbprint = $ClusterCertificateThumbprint
            ServerCertificateThumbprint = $ServerCertificateThumbprint
            ReverseProxyCertificateThumbprint = $ReverseProxyCertificateThumbprint
            AdminClientCertificateThumbprint = $AdminClientCertificateThumbprint
            NonAdminClientCertificateThumbprint = $NonAdminClientCertificateThumbprint
            DisableContainers = $DisableContainers
            StandaloneDeployment = $StandaloneDeployment
            ProviderIdentityApplicationId = $ProviderIdentityApplicationId
            ArmEndpoint = $ArmEndpoint
            AzureKeyVaultDnsSuffix = $AzureKeyVaultDnsSuffix
            AzureKeyVaultServiceEndpointResourceId = $AzureKeyVaultServiceEndpointResourceId
            ProviderIdentityTenantId = $ProviderIdentityTenantId
            ProviderIdentityCertCommonName = $ProviderIdentityCertCommonName
            SubscriptionName = $SubscriptionName
            DSCAgentConfig = $DSCAgentConfig
            BRSDisableKVAuthorityValidation = $BRSDisableKVAuthorityValidation
            PsDscRunAsCredential = $Credential
            DependsOn = '[xSfCertificatesPermit]ServiceFabricCertificatesPermissions'
        }
       
        xSfClusterNodesOps AddOrRejoinServiceFabricClusterNodes
        {
            DeploymentNodeIndex = $DeploymentNodeIndex
            VMNodeTypePrefix = $VMNodeTypePrefix
            VMNodeTypeInstanceCounts=$VMNodeTypeInstanceCounts
            CurrentVMNodeTypeIndex=$CurrentVMNodeTypeIndex
            ClientConnectionEndpointPort = $clientConnectionEndpointPort
            HTTPGatewayEndpointPort = $httpGatewayEndpointPort
            ReverseProxyEndpointPort = $reverseProxyEndpointPort
            EphemeralStartPort = $ephemeralStartPort
            EphemeralEndPort = $ephemeralEndPort
            ApplicationStartPort = $applicationStartPort
            ApplicationEndPort = $applicationEndPort
            ClientConnectionEndpoint = $ClientConnectionEndpoint
            ClusterCertificateCommonName = $ClusterCertificateCommonName
            ServerCertificateCommonName = $ServerCertificateCommonName
            ClusterCertificateThumbprint = $ClusterCertificateThumbprint
            ServerCertificateThumbprint = $ServerCertificateThumbprint
            DependsOn = '[xSfClusterCreateOps]CreateServiceFabricCluster'
        }

        LocalConfigurationManager 
        {
            ConfigurationMode = $($ConfigurationMode)
        }
    }
}