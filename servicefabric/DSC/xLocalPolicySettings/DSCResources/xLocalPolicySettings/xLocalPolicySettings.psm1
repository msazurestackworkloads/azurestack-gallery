function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex
    )
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    # V2: Assume GPO and security policy inf is in place in the image

    # Validate GPO is in place
    $gpoDestinationPath = "$env:windir\System32\GroupPolicy"
    $testGPOIniPath = Join-Path $gpoDestinationPath "gpt.ini"

    $gpoInPlace = Test-Path $testGPOIniPath

    if (-not $gpoInPlace)
    {
        Write-Warning "Pre-existing group policy is not in place on the image."
    }

    # Validate SPO file is in place
    $spoRootFolder = Join-Path $env:SystemDrive "VMSPO"
    $spoFilePath = Join-Path $spoRootFolder "securitypolicy.inf"

    $spoInPlace = Test-Path $spoFilePath

    if (-not $spoInPlace)
    {
        Write-Warning "Pre-existing security policy is not in place on the image."
    }

    # Fall back into the back compat way of applying security settings from the DSC zip file
    if ((-not $gpoInPlace) -or (-not $spoInPlace))
    {
        # Unpack the zip
        # Assumptions: 1. Policies zip file is located in the same path as the module. 2. The module will be dropped by the DSC extension at C:\Program Files\WindowsPowerShell\Modules

        $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
        $ModuleName = "xLocalPolicySettings"
        $ZipFileName = "xLocalPolicySettingsPolicies.zip"
        $ZipFilePath = "$PSModulePath\$ModuleName\DSCResources\$ModuleName\$ZipFileName"

        $zipFileExists = Test-Path -Path $ZipFilePath
        if (-not $zipFileExists)
        {
            Write-Warning "Policies zip file not found at expected path: '$ZipFilePath'" -ErrorAction Continue
        }
        else
        {
            # Extract the zip
            Write-Verbose "Policies zip file found at expected path: '$ZipFilePath' begining processing." -Verbose
            $driveLetter = (Get-Item $PSModulePath).PSDrive.Name
            $workingDir = "$driveLetter`:\secdb"

            # Create working directory if path does not exist
            if (-not (Test-Path -Path $workingDir))
            {
                Write-Verbose "Creating working directory '$workingDir'" -Verbose
                New-Item -Path $workingDir -ItemType Directory
            }

            # Extract the zip file to the working directory
            Expand-Archive -Path $ZipFilePath -DestinationPath $workingDir -Force
            Write-Verbose "Extracted policies zip file to '$workingDir'" -Verbose

            # apply group policies from zip file
            if (-not $gpoInPlace)
            {
                # Copy the group policy files
                $gpoFilesPath = "$workingDir\GPO\GroupPolicy"
                if (Test-Path -Path $gpoFilesPath)
                {
                    $gpoDestinationPath = "$env:windir\System32\GroupPolicy"
                    Copy-Item -Path "$gpoFilesPath\*" -Destination $gpoDestinationPath -recurse -Force
                    Write-Verbose "Applied group policy files"
                }
                else
                {
                    Write-Warning "Could not apply group policy on machine, source files not found at: '$gpoFilesPath'" -ErrorAction Continue
                }
            }

            # apply security policies from zip file
            if (-not $spoInPlace)
            {
                # Apply the security policy
                $secPolicyFilePath = "$workingDir\SPO\securitypolicy.inf"
                if (Test-Path -Path $secPolicyFilePath)
                {
                    $secDBPath = "$workingDir\secdb.sdb"
                    $logFilePath = "$workingDir\secdb.log"
                    & Secedit /configure /db $secDBPath /cfg $secPolicyFilePath /log $logFilePath /quiet
                    Write-Verbose "Applied security policy file" -Verbose
                }
                else
                {
                    Write-Warning "Could not apply security policy on machine, source file not found at: '$secPolicyFilePath'" -ErrorAction Continue
                }
            }

        }

    }
    else
    {
        # apply sec policy from the image
        $imageSecDBPath = Join-Path $spoRootFolder "secdb.sdb"
        $imageLogFilePath = Join-Path $spoRootFolder "secdb.log"
        & Secedit /configure /db $imageSecDBPath /cfg $spoFilePath /log $imageLogFilePath /quiet
        Write-Verbose "Applied security policy file from image" -Verbose
    }

    # Defender Updates
    $defenderUpdatesRootFolder = Join-Path $env:SystemDrive "DefenderUpdates"
    $defenderUpdatesRootFolderTest = Test-Path $defenderUpdatesRootFolder

    if ($defenderUpdatesRootFolderTest)
    {
        $updatePlatformAppliedPath = Join-Path $defenderUpdatesRootFolder "PlatformUpdated.txt"
        $platformUpdatedTest = Test-Path $updatePlatformAppliedPath
        
        # Defender platform has not been updated, apply update
        if (-not $platformUpdatedTest)
        {
            $platformUpdateFilePath = Join-Path $defenderUpdatesRootFolder "UpdatePlatform.exe"
            $platfrormUpdateFilePathTest = Test-Path $platformUpdateFilePath

            if ($platfrormUpdateFilePathTest)
            {
                # Platform update code based on Defender update code in Azure Stack Deploy repo
                try
                {
                    $process = [System.Diagnostics.Process]::new()
                    $process.StartInfo.FileName = $platformUpdateFilePath
                    $timeout = New-TimeSpan -Minutes 10

                    Write-Verbose "Updating Defender platform from file: '$platformUpdateFilePath'" -Verbose

                    $process.Start() | Out-Null
                    if (-not $process.WaitForExit($timeout.TotalMilliseconds))
                    {
                       Write-Warning "MoCAMP update process didn't finish within the time allocated ({0} seconds).`r`n" -f $timeout.TotalSeconds
                    }
                    else
                    {
                        Write-Verbose "Finished Updating Defender platform from file: '$platformUpdateFilePath'" -Verbose
                        New-Item -Path $updatePlatformAppliedPath -ItemType File -Force
                    }
                }
                catch
                {
                    Write-Warning "Failed to update Defender platform."
                    Write-Warning $_.Exception
                }
                finally 
                {
                    $process.Close()
                    $process = $null

                    $service = Get-Service -Name "windefend" -ErrorAction SilentlyContinue
                    if ($null -ne $service -and $service.Status -ine "Running")
                    {
                        $service | Start-Service -ErrorAction SilentlyContinue
                    }
                }
            }
            else
            {
                Write-Warning "Defender platform update file '$platformUpdateFilePath' not found, skipping Defender platform update."
            }
        }

        $updateDefinitionsAppliedPath = Join-Path $defenderUpdatesRootFolder "DefinitionsUpdated.txt"
        $definitionsUpdatedTest = Test-Path $updateDefinitionsAppliedPath
        
        # Defender definitions have not been updated, apply update
        if (-not $definitionsUpdatedTest)
        {
            # Defender definitions update 
            $definitionsUpdatesPath = Join-Path $defenderUpdatesRootFolder "x64"
            $definitionsUpdatesPathTest = Test-Path $definitionsUpdatesPath

            if ($definitionsUpdatesPathTest)
            {
                try
                {
                    Write-Verbose "Updating Defender definitions from path: '$definitionsUpdatesPath'" -Verbose
                    & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -SignatureUpdate -UNC -Path $defenderUpdatesRootFolder 2>&1

                    Write-Verbose "Finished Updating definitions from path: '$definitionsUpdatesPath'" -Verbose
                    New-Item -Path $updateDefinitionsAppliedPath -ItemType File -Force
                }
                catch
                {
                    Write-Warning "Fail to apply Microsoft Defender update at: $defenderSignatureFilePath."
                    Write-Warning $_.Exception
                }
            }
            else
            {
                Write-Warning "Defender definitions updates '$definitionsUpdatesPath' not found, skipping Defender definitions update."
            }
        }
    }
    else 
    {
        Write-Warning "'$defenderUpdatesRootFolder' path not found, skipping updating Defender."
    }

    # Defender scan exclusions for SF data drive paths.
    $regPath = 'HKLM\Software\Policies\Microsoft\Windows Defender'
    Set-Registry -Path $regPath -Name Exclusions -Value 1
    Set-Registry -Path $regPath -Name Scan -Value 1

    $regPath = 'HKLM\Software\Policies\Microsoft\Windows Defender\Exclusions'
    Set-Registry -Path $regPath -Name Exclusions_Paths -Value 1

    $regPath = 'HKLM\Software\Policies\Microsoft\Windows Defender\Exclusions\Paths'
    Set-Registry -Path $regPath -Name "E:\SF" -Value 0 -Type REG_SZ
    Set-Registry -Path $regPath -Name "E:\SFDiagnosticsStore" -Value 0 -Type REG_SZ
    Set-Registry -Path $regPath -Name "E:\SFSetup" -Value 0 -Type REG_SZ
    Set-Registry -Path $regPath -Name "E:\SFStandaloneLogs" -Value 0 -Type REG_SZ

    # Enable remote PS firewall rule
    $remotePSFirewallRule = Get-NetFirewallRule -DisplayName "TCP 5985 Public" -ErrorAction Ignore
    if ($null -eq $remotePSFirewallRule)
    {
        Write-Verbose "Creating firewall rule for port 5985 public profile" -Verbose
        New-NetFirewallRule -DisplayName "TCP 5985 Public" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 -Profile Public
    }
    else
    {
        Write-Verbose "Firewall rule for port 5985 public profile already exists" -Verbose
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex
    )

    # Creating the remote PS firewall rule is the last step, check if the rule exist. If it exists all policies have been applied
    $remotePSFirewallRule = Get-NetFirewallRule -DisplayName "TCP 5985 Public" -ErrorAction Ignore
    $result = $null -ne $remotePSFirewallRule

    return $result
}

function Set-Registry([string] $Path, [string] $Name, [string] $Value, [string] $Type)
{
    if(-not $Type)
    {
        $Type = 'REG_DWORD'
    }

    reg add $Path /v $Name /d $Value /t $Type /f
    
    if ($lastExitCode -ne 0)
    {
        throw  "Failed to update registry $Path/$Name"
    }
    else
    {
        Write-Output "Successfully updated registry $Path/$Name"
    }
}

Export-ModuleMember -Function *-TargetResource