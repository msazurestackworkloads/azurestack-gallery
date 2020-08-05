#
# xComputer: DSC resource to initialize, partition, and format disks. No restart
#

function Get-TargetResource
{
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [string] $DriveLetter
    )

    $disk = Get-Disk -Number $DiskNumber
    $returnValue = @{
        DiskNumber = $disk.Number
        DriveLetter = $disk | Get-Partition | Where-Object { $_.DriveLetter -ne "`0" } | Select-Object -ExpandProperty DriveLetter
    }
    $returnValue
}


# This function is to set CD/DVD drive letter to a new one. The reason to use it in Disk DSC is that the CD/DVD drive letter and service fabric data drive letter will be 
# swapped and changed after VMSS instance inplace upgrade or reimage. This function will be used before initializing the service fabric data disk, to keep the original drive 
# letter order.
function Set-DVDDriveLetter
{
    Param
    (
        [Parameter(Mandatory=$True,
        Position=1)]
        [string]
        [ValidatePattern("^[A-Z]{1}:{1}`$")]$NewDrvLetter
    )
    # Get Available CD/DVD Drive - Drive Type 5
    $DvdDrv = Get-WmiObject -Class Win32_Volume -Filter "DriveType=5"
    
    # Check if CD/DVD Drive is Available
    if ($DvdDrv -ne $null)
    {
        # Get Current Drive Letter for CD/DVD Drive
        $DvdDrvLetter = $DvdDrv | Select-Object -ExpandProperty DriveLetter
        Write-Verbose "Current CD/DVD Drive Letter is $DvdDrvLetter" -Verbose
    
        # Confirm New Drive Letter is NOT used
        if (-not (Test-Path -Path $NewDrvLetter))
        {
            # Change CD/DVD Drive Letter
            $DvdDrv | Set-WmiInstance -Arguments @{DriveLetter="$NewDrvLetter"}
            Write-Verbose "Updated CD/DVD Drive Letter as $NewDrvLetter" -Verbose
        }
        else
        {
           Write-Verbose "Drive Letter $NewDrvLetter Already In Use" -Verbose
        }
    }
    else
    {
        Write-Verbose "No CD/DVD Drive Available !!" -Verbose
    }
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [string] $DriveLetter
    )

    Set-DVDDriveLetter -NewDrvLetter 'F:'
    
    $disk = Get-Disk -Number $DiskNumber
    
    if ($disk.IsOffline -eq $true)
    {
        Write-Verbose 'Setting disk Online' -Verbose
        $disk | Set-Disk -IsOffline $false
    }
    
    if ($disk.IsReadOnly -eq $true)
    {
        Write-Verbose 'Setting disk to not ReadOnly' -Verbose
        $disk | Set-Disk -IsReadOnly $false
    }
    
    if ($disk.PartitionStyle -eq "RAW")
    {
        Write-Verbose -Message "Initializing disk number '$($DiskNumber)'..." -Verbose

        $disk | Initialize-Disk -PartitionStyle GPT -PassThru
        if ($DriveLetter)
        {
            $partition = $disk | New-Partition -DriveLetter $DriveLetter -UseMaximumSize
        }
        else
        {
            $partition = $disk | New-Partition -AssignDriveLetter -UseMaximumSize
        }

        # Sometimes the disk will still be read-only after the call to New-Partition returns.
        Start-Sleep -Seconds 5

        $volume = $partition | Format-Volume -FileSystem NTFS -Confirm:$false

        Write-Verbose -Message "Successfully initialized disk number '$($DiskNumber)'." -Verbose
    }
    
    if (($disk | Get-Partition | Where-Object { $_.DriveLetter -ne "`0" } | Select-Object -ExpandProperty DriveLetter) -ne $DriveLetter)
    {
        Write-Verbose "Changing drive letter to $DriveLetter"  -Verbose
        Set-Partition -DiskNumber $disknumber -PartitionNumber (Get-Partition -Disk $disk | Where-Object { $_.DriveLetter -ne "`0" } | Select-Object -ExpandProperty PartitionNumber) -NewDriveLetter $driveletter
    }
}

function Test-TargetResource
{
	[OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory)]
        [uint32] $DiskNumber,

        [string] $DriveLetter
    )

    Write-Verbose -Message "Checking if disk number '$($DiskNumber)' is initialized..." -Verbose
    $disk = Get-Disk -Number $DiskNumber
    if (-not $disk)
    {
        throw "Disk number '$($DiskNumber)' does not exist."
    }
    if ($disk.PartitionStyle -ne "RAW")
    {
        Write-Verbose "Disk number '$($DiskNumber)' has already been initialized." -Verbose

        $driveLetterFromDisk = $disk | Get-Partition | Where-Object { $_.DriveLetter -ne "`0" } | Select-Object -ExpandProperty DriveLetter
        if ($DriveLetter -ne "" -and $DriveLetter -ne $driveLetterFromDisk)
        {
            write-verbose "Disk number '$($DiskNumber)' has an unexpected drive letter. Expected: $DriveLetter. Actual: $driveLetterFromDisk." -Verbose
            return $false
        }
        if ($disk.IsOffline -eq $true) 
        {
            write-verbose "Disk is set Offline." -Verbose
            return $false
        }
        if ($disk.IsReadOnly -eq $true) 
        {
            write-verbose "Disk is set ReadOnly." -Verbose
            return $false
        }
        return $true
    }
    return $false
}

Export-ModuleMember -Function *-TargetResource