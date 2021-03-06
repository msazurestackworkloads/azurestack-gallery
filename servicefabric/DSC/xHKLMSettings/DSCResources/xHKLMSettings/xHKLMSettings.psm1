function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $DisableStrongNameValidation
    )
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $DisableStrongNameValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    # SF deployment workflow stage 1.2: Host Provision: Configure HKLM settings
    #     Running on every node, preparing environment for service fabric installnation.

    # Set TLS setting for 4.5.2 Framework based applications to default to TLS 1.2 version
    $cryptoKeyPath = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
    $cryptoKeyPathSide = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
    $cryptoKeyName = "SchUseStrongCrypto"
    $value = 1
	
    Write-Verbose "Going to set TLS setting $cryptoKeyName under $cryptoKeyPath" -Verbose
    New-ItemProperty -Path $cryptoKeyPath -Name $cryptoKeyName -Value $value -PropertyType DWORD -Force
	
    Write-Verbose "Going to set TLS setting $cryptoKeyName under $cryptoKeyPathSide" -Verbose
    New-ItemProperty -Path $cryptoKeyPathSide -Name $cryptoKeyName -Value $value -PropertyType DWORD -Force

    # BEGIN TEMP SECTION

    # BEGIN COMMENT ---- Commenting Disabling of Strong name verification for Release
    # Disable strong name validation

    if ($DisableStrongNameValidation)
    {
        Write-Verbose "Skipping strong name verification started"
        Remove-Item "HKLM:\Software\Microsoft\StrongName\Verification" -Recurse -Force -ErrorAction Ignore
        New-Item -Path "HKLM:\Software\Microsoft\StrongName\Verification\*,*" -Force

        if ([Environment]::Is64BitOperatingSystem)
        {
            Write-Verbose "Identified as 64 bit operating system"
            Remove-Item "HKLM:\Software\Wow6432Node\Microsoft\StrongName\Verification" -Recurse -Force -ErrorAction Ignore
            New-Item -Path "HKLM:\Software\Wow6432Node\Microsoft\StrongName\Verification\*,*" -Force
        }

        Write-Verbose "Skipping strong name verification completed"
    }

    # END COMMENT ---- Commenting Disabling of Strong name verification for Release

    # END TEMP SECTION
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $DisableStrongNameValidation
    )

    return $false
}

Export-ModuleMember -Function *-TargetResource