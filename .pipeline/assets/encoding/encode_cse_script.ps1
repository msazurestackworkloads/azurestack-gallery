function ConvertTo-GzipData {
    [cmdletBinding()]
    param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [byte[]]$Data
    )
       
    $output = [System.IO.MemoryStream]::new()
    $gzipStream = New-Object System.IO.Compression.GzipStream $output, ([IO.Compression.CompressionLevel]::Optimal)
              
    $gzipStream.Write($Data, 0, $Data.Length)
    $gzipStream.Close()
    return $output.ToArray()
}

function ConvertTo-Base64String {
    [cmdletBinding()]
    param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [byte[]]$Data
    )
    return [Convert]::ToBase64String($Data)
}

function ConvertTo-Bytes {
    [cmdletBinding()]
    param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$Data
    )
    $enc = [system.Text.Encoding]::Unicode  
    return $enc.GetBytes($Data) 
}

function Replace-NewLine {
    [cmdletBinding()]
    param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$Data
    )
    
    $Data = $Data.Replace("`r`n", "`n")
    return $Data
}

function Escape-SingleLine {
    [cmdletBinding()]
    param(
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$Data
    )
    $Data = $Data.Replace("`\", "\\\\")
    $Data = $Data.Replace("`r`n", "\n")
    $Data = $Data.Replace("`n", "\n")
    $Data = $Data.Replace("`"", "\`"")
    return $Data
}

$scriptstring=Get-Content -Raw .\script.sh | Replace-NewLine
$bytes = ConvertTo-Bytes -Data $scriptstring
$gizipData = ConvertTo-GzipData -Data $bytes
$scriptstring = ConvertTo-Base64String -Data $gizipData
$scriptstring

$customerString=Get-Content -Raw "encode_CustomData.t"
$customerString= $customerString.Replace("SCRIPT_PLACEHOLDER",$scriptstring) | Replace-NewLine | Escape-SingleLine

"`"customData`": `"[base64(concat('$customerString'))]`"," > script.b64