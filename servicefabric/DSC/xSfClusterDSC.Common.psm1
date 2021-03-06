# Provision util functions
function IsMasterNode
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex
    )

    # NodeType name, Node name are required to use upper case to avoid case sensitive issues
    $VMNodeTypePrefix = $VMNodeTypePrefix.ToUpper()
    $vmNodeTypeName = "$VMNodeTypePrefix$CurrentVMNodeTypeIndex"

    # Get the decimal based index of the VM machine name (VM Scale set name the machines in the format {Prefix}{Suffix}
    # where Suffix is a 6 digit base36 number starting from 000000 to zzzzzz.
    # Get the decimal index of current node and match it with the index of required deployment node.
    $scaleSetDecimalIndex = ConvertFrom-Base36 -base36Num ($env:COMPUTERNAME.ToUpper().Substring(($vmNodeTypeName).Length))

    # Check if current Node is master node.
    $isMasterNode = $scaleSetDecimalIndex -eq $DeploymentNodeIndex -and $CurrentVMNodeTypeIndex -eq 0

    return $isMasterNode
}

function IsServiceFabricInstalledOnNode
{
    return Test-Path 'HKLM:\SOFTWARE\Microsoft\Service Fabric'
}

function ConnectClusterWithRetryAndExceptionThrown
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $SetupDir,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [System.String]
        $ServerCertificateThumbprint,

        [System.String]
        $ClusterCertificateThumbprint,

        [System.Int32]
        $TimeoutTimeInMin = 5,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    Write-Verbose "Trying to connect to Service Fabric cluster $ClientConnectionEndpoint" -Verbose

    $ServiceFabricPowershellModulePath = Get-ServiceFabricPowershellModulePath -SetupDir $SetupDir
    Import-Module $ServiceFabricPowershellModulePath -ErrorAction SilentlyContinue -Verbose:$false

    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)

    while((Get-Date) -lt $timeoutTime)
    {
        try
        {   
            $connection = Connect-ServiceFabricCluster -X509Credential `
                                    -ConnectionEndpoint $ClientConnectionEndpoint `
                                    -ServerCertThumbprint $ServerCertificateThumbprint `
                                    -StoreLocation "LocalMachine" `
                                    -StoreName "My" `
                                    -FindValue $ClusterCertificateThumbprint `
                                    -FindType FindByThumbprint `
                                    -TimeoutSec 10

            if($connection -and $connection[0])
            {
                Write-Verbose "Service Fabric connection succeed." -Verbose
                return $true
            }
            else
            {
                throw "Connection to service fabric cluster is closed: $connection"
            }
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "Connection failed because: $lastException. Retrying until $timeoutTime." -Verbose
            Write-Verbose "Waiting for $($TimeoutBetweenProbsInSec) seconds..." -Verbose
            Start-Sleep -Seconds $TimeoutBetweenProbsInSec
        }
    }

    Write-Verbose "Service Fabric connection failed." -Verbose
    
    if ($null -ne $lastException)
    {
        throw $lastException
    }
    
    return $false
}

function ConnectClusterWithRetryAndExceptionSwallowed
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $SetupDir,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [System.String]
        $ServerCertificateThumbprint,

        [System.String]
        $ClusterCertificateThumbprint,

        [System.Int32]
        $TimeoutTimeInMin = 5,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    $connectSucceeded = $false

    try
    {
        $connectSucceeded = ConnectClusterWithRetryAndExceptionThrown -SetupDir $setupDir `
            -ClientConnectionEndpoint $ClientConnectionEndpoint `
            -ServerCertificateThumbprint $ServerCertificateThumbprint `
            -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
            -TimeoutTimeInMin $TimeoutTimeInMin `
            -TimeoutBetweenProbsInSec $TimeoutBetweenProbsInSec
    }
    catch
    {
        $lastException = $_.Exception
        Write-Verbose "Connection failed with exception swallowed. Last exception thrown: $lastException." -Verbose
    }

    return $connectSucceeded
}

function IsClusterHealthy
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateThumbprint,

        [System.Int32]
        $TimeoutTimeInMin = 5,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    Write-Verbose "Trying to get health state for Service Fabric cluster $ClientConnectionEndpoint" -Verbose

    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)
    $isHealthy = $false
    
    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    do
    {
        try
        {
            # Connecting to secure cluster: 
            # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-connect-to-secure-cluster#connect-to-a-secure-cluster-using-a-client-certificate
            Connect-ServiceFabricCluster -X509Credential `
                            -ConnectionEndpoint $ClientConnectionEndpoint `
                            -ServerCertThumbprint $ServerCertificateThumbprint `
                            -StoreLocation "LocalMachine" `
                            -StoreName "My" `
                            -FindValue $ClusterCertificateThumbprint `
                            -FindType FindByThumbprint `
                            -TimeoutSec 10 `
                            | Out-Null

            $Error.Clear()
            $healthReport = Get-ServiceFabricClusterHealth #Get-ServiceFabricClusterHealth ToString is bugged, so calling twice
            $healthReport = Get-ServiceFabricClusterHealth
            $currentHealthState = $healthReport.AggregatedHealthState
        
            if($currentHealthState -ne "Ok")
            {
                Write-Verbose "Cluster aggregated health state is not OK, saw $currentHealthState. Waiting for $($TimeoutBetweenProbsInSec) seconds, retrying until $timeoutTime." -Verbose
                Start-Sleep -Seconds $TimeoutBetweenProbsInSec
            }
            else
            {
                Write-Verbose "Service Fabric cluster is healthy." -Verbose
                $isHealthy = $true
            }
        }
        catch [System.Fabric.FabricTransientException]
        {
            Write-Verbose "Service Fabric transient exception: $_.Exception"
        }
    } while((-not $isHealthy) -and ((Get-Date) -lt $timeoutTime))

    return $isHealthy
}

function IsClusterUpgradeComplete {
    param(
        [parameter(Mandatory = $true)]
        [System.String]
        $SetupDir,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $TargetVersion,

        [System.Int32]
        $TimeoutTimeInMin = 60 # Waitng 1h max for configuarion upgrade
    )

    $ServiceFabricPowershellModulePath = Get-ServiceFabricPowershellModulePath -SetupDir $SetupDir
    Import-Module $ServiceFabricPowershellModulePath -ErrorAction SilentlyContinue -Verbose:$false

    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    # Monitoring status. Reference: https://docs.microsoft.com/en-us/dotnet/api/system.fabric.fabricupgradestate?view=azure-dotnet
    Write-Verbose "Start monitoring cluster configration update..." -Verbose

    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)

    while ((Get-Date) -lt $timeoutTime) {
        try {

            # Connecting to secure cluster: 
            # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-connect-to-secure-cluster#connect-to-a-secure-cluster-using-a-client-certificate
            Write-Verbose "Trying to connect to Service Fabric cluster $ClientConnectionEndpoint" -Verbose

            Connect-ServiceFabricCluster -X509Credential `
                                    -ConnectionEndpoint $ClientConnectionEndpoint `
                                    -ServerCertThumbprint $ServerCertificateThumbprint `
                                    -StoreLocation "LocalMachine" `
                                    -StoreName "My" `
                                    -FindValue $ClusterCertificateThumbprint `
                                    -FindType FindByThumbprint `
                                    -TimeoutSec 10 `
                                    | Out-Null

            $udStatus = Get-ServiceFabricClusterConfigurationUpgradeStatus

            # FabricUpgradeState Enum: https://docs.microsoft.com/en-us/dotnet/api/system.fabric.fabricupgradestate?view=azure-dotnet

            if ($udStatus.UpgradeState -eq 'RollingForwardCompleted' -and $udStatus.ConfigVersion -eq $TargetVersion) {
                # Terminate monitoring if update complate.
                Write-Verbose "Cluster configration update completed. Current state: $($udStatus.UpgradeState). Current version: $($udStatus.ConfigVersion)." -Verbose
                return $true
            }

            # Other situations will be considered updating in progress.
            Write-Verbose "Updating Service Fabric cluster configuration in progress. Current state: $($udStatus.UpgradeState). Current version: $($udStatus.ConfigVersion). Waiting for 60 seconds..." -Verbose
            Start-Sleep -Seconds 30
        }
        catch {
            $lastException = $_.Exception
            Write-Verbose "Upgrade status check failed because: $lastException. Retrying until $timeoutTime." -Verbose
            Write-Verbose "Waiting for 60 seconds..." -Verbose
            Start-Sleep -Seconds 60
        }
    }

    Write-Verbose "Update cluster configration times out." -Verbose
    return $false
}

function IsNodeUpAndRunning
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $NodeName,

        [System.Int32]
        $TimeoutTimeInMin = 5,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    Write-Verbose "Trying to get node $NodeName from Service Fabric cluster $ClientConnectionEndpoint" -Verbose

    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)
    $isNodeUpAndRunning = $false
    
    do
    {
        # Connecting to secure cluster: 
        # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-connect-to-secure-cluster#connect-to-a-secure-cluster-using-a-client-certificate
        Connect-ServiceFabricCluster -X509Credential `
                            -ConnectionEndpoint $ClientConnectionEndpoint `
                            -ServerCertThumbprint $ServerCertificateThumbprint `
                            -StoreLocation "LocalMachine" `
                            -StoreName "My" `
                            -FindValue $ClusterCertificateThumbprint `
                            -FindType FindByThumbprint `
                            -TimeoutSec 10 `
                            | Out-Null

            $sfNodes = Get-ServiceFabricNode | % {$_.NodeName}
   
            if($sfNodes -contains $NodeName)
            {
                $currentNode = Get-ServiceFabricNode | Where-Object {$_.NodeName -eq $NodeName}

                if($currentNode.NodeStatus -eq "Up")
                {
                    Write-Verbose "Current node '$NodeName' is $($currentNode.NodeStatus)." -Verbose
                    $isNodeUpAndRunning = $true
                }
                else
                {
                    Write-Verbose "Current node status is not Up and Running, saw $($currentNode.NodeStatus). Waiting for $($TimeoutBetweenProbsInSec) seconds, retrying until $timeoutTime." -Verbose
                    Start-Sleep -Seconds $TimeoutBetweenProbsInSec
                }
            }
        } while((-not $isNodeUpAndRunning) -and ((Get-Date) -lt $timeoutTime))

    return $isNodeUpAndRunning
}

function ConvertTo-Base36
{
    [CmdletBinding()]
    param ([int]$decNum="")

    $alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    do
    {
        $remainder = ($decNum % 36)
        $char = $alphabet.substring($remainder,1)
        $base36Num = "$char$base36Num"
        $decNum = ($decNum - $remainder) / 36
    }
    while ($decNum -gt 0)

    return $base36Num
}

function ConvertFrom-Base36
{
    param
    (
        [String] $base36Num
    )

    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"

    $inputarray = $base36Num.tolower().tochararray()
    [array]::reverse($inputarray)
                
    [long]$decimalIndex=0
    $pos=0

    foreach ($c in $inputarray)
    {
        $decimalIndex += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
        $pos++
    }

    return $decimalIndex
}

function Get-ServiceFabricPowershellModulePath
{
    param 
    (
        [string] $SetupDir
    )

    $serviceFabricDir = Join-Path $SetupDir -ChildPath "ServiceFabric"
    $DeployerBinPath = Join-Path $serviceFabricDir -ChildPath "DeploymentComponents"
    $ServiceFabricPowershellModulePath = Join-Path $DeployerBinPath -ChildPath "ServiceFabric.psd1"

    return $ServiceFabricPowershellModulePath
}

function Get-CertLatestThumbPrintByCommonName
{
    param
    (
        [System.String]
        $SubjectName
    )

    return (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.SubjectName.Name -eq $subjectName } | Sort-Object -Property NotAfter | Select-Object -last 1).Thumbprint
}

function Get-CertSubjectNameByThumbprint
{
    param
    (
        [System.String]
        $Thumbprint
    )

    return ((Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint` }).Subject  -split ',*..=')[1]
}

function Grant-CertAccess
{
    param
    (
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SubjectName,

        [Parameter(Position=2, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServiceAccount,

        [Parameter(Position=3)]
        [System.Boolean]
        $IsCertRequired = $true
    )

    # The list of the certs with the same Common name, might be multiple after SR
    $certs = Get-ChildItem -Path cert:\LocalMachine\My | Where-Object -FilterScript { $PSItem.SubjectName.Name -eq $SubjectName; }
    
    if ($certs.Count -lt 1)
    {
        $errorMessage = "$($certs.Count) certificate(s) with $SubjectName found."

        if ($IsCertRequired)
        {
            Write-Error -Exception $errorMessage
            throw
        }

        Write-Verbose $errorMessage -Verbose
    }

    foreach ($cert in $certs)
    {
        # Specify the user, the permissions, and the permission type
        $permission = "$($ServiceAccount)","FullControl","Allow"
        $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission

        # Location of the machine-related keys
        $keyPath = Join-Path -Path $env:ProgramData -ChildPath "\Microsoft\Crypto\RSA\MachineKeys"
        $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
        $keyFullPath = Join-Path -Path $keyPath -ChildPath $keyName

        # Get the current ACL of the private key
        $acl = (Get-Item $keyFullPath).GetAccessControl('Access')

        # Add the new ACE to the ACL of the private key
        $acl.SetAccessRule($accessRule)

        # Write back the new ACL
        Set-Acl -Path $keyFullPath -AclObject $acl -ErrorAction Stop

        # Observe the access rights currently assigned to this certificate
        get-acl $keyFullPath| fl
    }
}

function Get-NodeName
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypeName,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $NodeIndex
    )

    $nodeName = "_" + $VMNodeTypeName + "_" + $NodeIndex

    return $nodeName
}

function Wait-ForAllNodesReadiness
{
    param
    (
        [System.UInt32[]] 
        $InstanceCounts,

        [System.String]
        $VMNodeTypePrefix,

        [System.String[]]
        $CertificateThumbprints = @(),

        [System.String[]]
        $CertificateNeedNetworkServicePermissionThumbprints = @(),

        [System.Int32]
        $TimeoutTimeInMin = 20, # Default DSC refresh interval is 15 mins

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    # Removes null and empty item from arrays.
    $certificateThumbprintsWithoutEmpty = @($CertificateThumbprints | Where-Object {-not [string]::IsNullOrEmpty($_)})
    $certificateNeedNetworkServicePermissionThumbprintsWithoutEmpty = @($CertificateNeedNetworkServicePermissionThumbprints | Where-Object {-not [string]::IsNullOrEmpty($_)})

    # Wait till all other nodes are ready.
    try
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force

        $timeoutTime = (Get-Date).AddMinutes($TimeoutTimeInMin)

        # Monitoring
        do
        {
            $areAllNodesReady = $true
            for($j = 0; $j -lt $InstanceCounts.Count; $j++)
            {
                $InstanceCount = $InstanceCounts[$j]
                $VMNodeTypeName = "$VMNodeTypePrefix$j"
                
                for($i = 0; $i -lt $InstanceCount; $i++)
                {
                    [String] $base36Index = (ConvertTo-Base36 -decNum $i)
                    $computerName = $VMNodeTypeName + $base36Index.PadLeft(6, "0")
                    $nodeName = Get-NodeName -VMNodeTypeName $VMNodeTypeName -NodeIndex $i
                
                    Write-Verbose "Checking node $nodeName (computer name: $computerName) ..." -Verbose
                    try
                    {
                        $nodeIsReady = Invoke-Command -ScriptBlock {
                                                    $isExpectedPermission = $true
                                                    $Using:certificateThumbprintsWithoutEmpty | % {
                                                            $certThumbprint = $_
                                                            $cert = dir Cert:\LocalMachine\My\ | ? {$_.Thumbprint -eq "$certThumbprint"}

                                                            if(-not $cert)
                                                            {
                                                                throw "Can't find certificate with thumbprint $certThumbprint."
                                                            }

                                                            if (($Using:certificateNeedNetworkServicePermissionThumbprintsWithoutEmpty).Contains($certThumbprint))
                                                            {
                                                                $rsaFile = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                                                                $keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\"
                                                                $fullPath = Join-Path $keyPath $rsaFile
                                                                $acl = Get-Acl -Path $fullPath -ErrorAction SilentlyContinue
                                                                $permission = ($acl.Access | ? {$_.IdentityReference -eq "NT AUTHORITY\NETWORK SERVICE"}).FileSystemRights
                                                                $isExpectedPermission = $isExpectedPermission -and ($permission -eq "FullControl")
                                                            }
                                                    }
                                                    return $isExpectedPermission
                                        } -ComputerName $computerName -ErrorAction Stop
                        
                        if($nodeIsReady)
                        {
                            Write-Verbose "Node '$nodeName (computer name: $computerName)' is ready." -Verbose
                        }
                        else
                        {
                            Write-Verbose "Node '$nodeName (computer name: $computerName)' is not ready." -Verbose
                        }

                        $areAllNodesReady =  $areAllNodesReady -and $nodeIsReady
                    }
                    catch
                    {
                        Write-Verbose "Failed to checking node '$nodeName (computer name: $computerName)'. Continue monitoring... $_" -Verbose
                        $areAllNodesReady = $false
                    }
                }
            }

            if(-not $areAllNodesReady)
            {
                Write-Verbose "Some node(s) are not ready. Waiting for $($TimeoutBetweenProbsInSec) seconds..." -Verbose
                sleep -Seconds $TimeoutBetweenProbsInSec
            }
            else
            {
                Write-Verbose "All nodes are ready!" -Verbose
                break
            }

        } while((-not $areAllNodesReady) -and ((Get-Date) -lt $timeoutTime))

        if(-not $areAllNodesReady)
        {
            throw "Timed out while waiting for other nodes."
        }
    }
    finally
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "" -Force
    }
}

function Get-ServiceFabricClusterConfigurationJson {
    param(
        [parameter(Mandatory = $true)]
        [System.String]
        $SetupDir,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [System.Int32]
        $TimeoutTimeInMin = 5,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 30
    )

    $ServiceFabricPowershellModulePath = Get-ServiceFabricPowershellModulePath -SetupDir $SetupDir
    Import-Module $ServiceFabricPowershellModulePath -ErrorAction SilentlyContinue -Verbose:$false

    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)

    while ((Get-Date) -lt $timeoutTime) {
        try {
            # Connecting to secure cluster: 
            # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-connect-to-secure-cluster#connect-to-a-secure-cluster-using-a-client-certificate
            Connect-ServiceFabricCluster -X509Credential `
                -ConnectionEndpoint $ClientConnectionEndpoint `
                -ServerCertThumbprint $ServerCertificateThumbprint `
                -StoreLocation "LocalMachine" `
                -StoreName "My" `
                -FindValue $ClusterCertificateThumbprint `
                -FindType FindByThumbprint `
            | Out-Null

            Write-Verbose "Service Fabric connection successful. Getting the Service Fabric Configuration..." -Verbose
            $sfConfig = Get-ServiceFabricClusterConfiguration
            return $sfConfig
        }
        catch {
            $lastException = $_.Exception
            Write-Verbose "Connect Service Fabric Cluster failed because: $lastException. Retrying until $timeoutTime." -Verbose
            Write-Verbose "Waiting for $TimeoutBetweenProbsInSec seconds..." -Verbose
            Start-Sleep -Seconds $TimeoutBetweenProbsInSec
        }
    }

    Write-Verbose "Get Service Fabric cluster configuration times out." -Verbose
    return $null
}

function Get-VMNodeTypeInstanceCountsFromClusterConfig {
    [OutputType([System.Int32[]])]
    param(
        [parameter(Mandatory = $true)]
        [System.String]
        $SetupDir,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.Int32[]]
        $InitialClusterSizes,

        [System.Int32]
        $TimeoutTimeInMin = 1,

        [System.Int32]
        $TimeoutBetweenProbsInSec = 15
    )

    $sfClusterConfig = Get-ServiceFabricClusterConfigurationJson -SetupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
        -TimeoutTimeInMin $TimeoutTimeInMin `
        -TimeoutBetweenProbsInSec $TimeoutBetweenProbsInSec

    if ($null -eq $sfClusterConfig)
    {
        Write-Verbose "Failed to get SF cluster configuration. Returns initial cluster sizes: $InitialClusterSizes" -Verbose
        return $InitialClusterSizes
    }

    $sfClusterConfigObject = ConvertFrom-Json -InputObject $sfClusterConfig

    [array]$VMNodeTypeInstanceCountsFromClusterConfig = @()
    $sfClusterConfigObject.Nodes `
        | Sort-Object -Property NodeTypeRef `
        | Group-Object -Property NodeTypeRef `
        | ForEach-Object { $VMNodeTypeInstanceCountsFromClusterConfig += $_.Count }

    Write-Verbose "Succeed to get SF cluster configuration. Returns cluster size: $VMNodeTypeInstanceCountsFromClusterConfig" -Verbose
    return $VMNodeTypeInstanceCountsFromClusterConfig
}

function Get-VMSSCredentialFromKeyvault {
    [OutputType([System.Management.Automation.PSCredential])]
   param
   (
       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityApplicationId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ArmEndpoint,

       [Parameter(Mandatory = $true)]
       [System.String]
       $AzureKeyVaultDnsSuffix,

       [Parameter(Mandatory = $true)]
       [System.String]
       $AzureKeyVaultServiceEndpointResourceId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityTenantId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityCertCommonName,

       [Parameter(Mandatory = $true)]
       [System.String]
       $SubscriptionName,

       [Parameter(Mandatory = $true)]
       [System.String]
       $VmssPwdVaultName,

       [Parameter(Mandatory = $true)]
       [System.String]
       $VmssPwdSecretName,

       [Parameter(Mandatory = $true)]
       [System.String]
       $AdminUserName
   )

   Write-Verbose "Start Get-VMSSCredentialFromKeyvault..." -Verbose

   Connect-AzureStackAdminEnvironment -ProviderIdentityApplicationId $ProviderIdentityApplicationId `
       -ArmEndpoint $ArmEndpoint `
       -AzureKeyVaultDnsSuffix $AzureKeyVaultDnsSuffix `
       -AzureKeyVaultServiceEndpointResourceId $AzureKeyVaultServiceEndpointResourceId `
       -ProviderIdentityTenantId $ProviderIdentityTenantId `
       -ProviderIdentityCertSubjectName "CN=$ProviderIdentityCertCommonName" `
       -SubscriptionName $SubscriptionName `
       | Out-Null

   Import-Module AzureRM.KeyVault -RequiredVersion 4.2.0 -Verbose:$false

   $passwordList = Get-AzureKeyVaultSecret -VaultName $VmssPwdVaultName -Name $VmssPwdSecretName -IncludeVersions

   foreach ($password in $passwordList) {
       Write-Verbose "Getting secret from keyvault with version: $($password.Version)..." -Verbose

       if ($password.Enabled) {
           $pwdItem = Get-AzureKeyVaultSecret -VaultName $VmssPwdVaultName -Name $VmssPwdSecretName -Version $password.Version
           Write-Verbose "The secret item: $pwdItem" -Verbose

           $Credential = $(New-Object System.Management.Automation.PSCredential("$($env:userdomain)\$AdminUserName", $pwditem.SecretValue))

           $session = New-PSSession -Credential $Credential -ErrorAction SilentlyContinue

           if (($null -ne $session) -and ($session.Availability -eq 'Available') -and ($session.State -eq 'Opened')) {
               Write-Verbose "Found avaliable session: $session with AdminUserName: $AdminUserName, Secret Version: $($password.Version), Secret enabled: $($password.Enabled)" -Verbose
               return $Credential
           }
       }

       Write-Verbose "Cannot create session with AdminUserName: $AdminUserName, Secret Version: $($password.Version), Secret enabled: $($password.Enabled)" -Verbose
   }

   Write-Verbose "No session created because no $VmssPwdSecretName from $VmssPwdVaultName is qualified." -Verbose
   return $null
}

function Connect-AzureStackAdminEnvironment {
   param
   (
       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityApplicationId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ArmEndpoint,

       [Parameter(Mandatory = $true)]
       [System.String]
       $AzureKeyVaultDnsSuffix,

       [Parameter(Mandatory = $true)]
       [System.String]
       $AzureKeyVaultServiceEndpointResourceId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityTenantId,

       [Parameter(Mandatory = $true)]
       [System.String]
       $ProviderIdentityCertSubjectName,

       [Parameter(Mandatory = $true)]
       [System.String]
       $SubscriptionName
   )
   
   Write-Verbose "Start Connect-AzureStackAdminEnvironment..." -Verbose

   Import-Module AzureRM.Profile -RequiredVersion 5.8.3 -Verbose:$false
   
   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
   $armMetadata = Invoke-RestMethod -Method Get -Uri ([uri]::new([uri]::new($ArmEndpoint, 'Absolute'), '/metadata/endpoints?api-version=1.0'))
   Add-AzureRmEnvironment -Name AzureStackAdmin -ArmEndpoint $ArmEndpoint | Out-Null

   $params = @{
       Name                                   = 'AzureStackAdmin'
       AzureKeyVaultDnsSuffix                 = $AzureKeyVaultDnsSuffix
       AzureKeyVaultServiceEndpointResourceId = $AzureKeyVaultServiceEndpointResourceId
       GraphAudience                          = $armMetadata.graphEndpoint
   }

   Set-AzureRmEnvironment @params | Out-Null
   Write-Verbose (Get-AzureRmEnvironment -Name AzureStackAdmin | Format-List | Out-String) -Verbose
   Write-Verbose "Provider identity certificate subject name is $ProviderIdentityCertSubjectName" -Verbose
   Write-Verbose "Subscription name is $SubscriptionName" -Verbose

   $clientCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -SubjectName $ProviderIdentityCertSubjectName
   Write-Verbose "The thumbprint of Provider identity certificate used to Connect-AzureRmAccount is $clientCertificateThumbprint" -Verbose

   $params = @{
       Environment           = 'AzureStackAdmin'
       ServicePrincipal      = $true
       ApplicationId         = $ProviderIdentityApplicationId
       CertificateThumbprint = $clientCertificateThumbprint
       TenantId              = $ProviderIdentityTenantId
       Subscription          = $SubscriptionName
   }
   $params | Out-Host

   Connect-AzureRmAccount @params | Out-Host
}

function Set-TargetResourceInternalWrapper {
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderIdentityApplicationId,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $ArmEndpoint,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $AzureKeyVaultDnsSuffix,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $AzureKeyVaultServiceEndpointResourceId,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderIdentityTenantId,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderIdentityCertCommonName,
        
        [Parameter(Mandatory = $true)]
        [System.String]
        $SubscriptionName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DSCResourceName,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $SetTargetResourceInternalParam,

        [Parameter(Mandatory = $true)]
        [string]
        $AdminUserName,

        [Parameter(Mandatory = $false)]
        [System.String]
        $DSCAgentConfig
    )

    Write-verbose "Execute start as ${env:username}" -Verbose

    $DSCAgentConfigObject = $DSCAgentConfig | ConvertFrom-Json
    Write-Verbose "Read DSCAgentConfig: $($DSCAgentConfigObject | ConvertTo-Json -Depth 99)" -Verbose
    $PwdConfigObject = $DSCAgentConfigObject.PwdConfig
    $VMSSPwdVaultName = $PwdConfigObject.VMSSPwd.vaultName
    $VMSSPwdSecretName = $PwdConfigObject.VMSSPwd.secretName

    $VMSSCredential = Get-VMSSCredentialFromKeyvault -ProviderIdentityApplicationId $ProviderIdentityApplicationId `
        -ArmEndpoint $ArmEndpoint `
        -AzureKeyVaultDnsSuffix $AzureKeyVaultDnsSuffix `
        -AzureKeyVaultServiceEndpointResourceId $AzureKeyVaultServiceEndpointResourceId `
        -ProviderIdentityTenantId $ProviderIdentityTenantId `
        -ProviderIdentityCertCommonName $ProviderIdentityCertCommonName `
        -SubscriptionName $SubscriptionName `
        -VmssPwdVaultName $VMSSPwdVaultName `
        -VmssPwdSecretName $VMSSPwdSecretName `
        -AdminUserName $AdminUserName

    if ($null -eq $VMSSCredential) {
        throw "No available VMSS credentials found in key vault. Password config: $($PwdConfigObject | ConvertTo-Json -Depth 99)."
    }

    $session = New-PSSession -Credential $VMSSCredential -computername localhost -Authentication CredSSP

    Invoke-Command -Session $session -ScriptBlock {
        Write-verbose "Execute start as ${env:username}" -Verbose
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
        $VerbosePreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

        # Import DSCResource in order to use Set-TargetResourceInternal function.
        $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
        $DSCResourceModulePath = "$PSModulePath\$Using:DSCResourceName\DSCResources\$Using:DSCResourceName"
        Import-Module $DSCResourceModulePath -Verbose:$false

        Set-TargetResourceInternal @Using:SetTargetResourceInternalParam

        Write-verbose "Execute end as ${env:username}" -Verbose
    }
    Write-verbose "Execute end as ${env:username}" -Verbose
}