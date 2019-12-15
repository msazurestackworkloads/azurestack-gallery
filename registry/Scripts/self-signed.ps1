#requires -runasadministrator
<#
.Synopsis
  The script provide functionality to create self signed certificate.

.Description
  The script provide functionality to create self signed certificate.

.Parameter CertificateCN
  Certificate common name.

.Parameter CertificatePassword
  Certificate Password.

.Parameter CertificateFileExportPath
  Certificate file export path including certificate filename.

.Parameter GenerateWildCardCert
  Flag to generate wild card cert.

.Example
   Self-Signed.ps1 -CertificateCN "registry.local.microsoft.com" 
                   -CertificatePassword <Secret>
                   -CertificateFileExportPath c:\certificate\registry_cert.pfx
#>
Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Certificate common name.")]
    [string] $CertificateCN,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate Password.")]
    [string] $CertificatePassword,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate file export path including certificate filename.")]
    [string] $CertificateFileExportPath,
    [Parameter(Mandatory = $false, HelpMessage = "Flag to generate wild card cert.")]
    [bool] $GenerateWildCardCert = $false
)

if (-not (Test-Path -Path $CertificateFileExportPath -IsValid))
{
  throw "Error: CertificateFileExportPath is not a valid path."
}

if (Test-Path -Path $CertificateFileExportPath)
{
  throw "Error: File($CertificateFileExportPath) already exist. Please remove to provide a different name."
}

# Create a self-signed certificate
if ($GenerateWildCardCert){
  Write-Host "Generating wildcard cert for $CertificateCN."
  $ssc = New-SelfSignedCertificate -Subject *.$CertificateCN -certstorelocation cert:\LocalMachine\My -dnsname $CertificateCN, *.$CertificateCN
}
else {
  Write-Host "Generating normal cert for $CertificateCN."
  $ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $CertificateCN
}

if ($ssc){
  Write-Host "Certificate created successfully. Now exporting the certificate."
}
else {
  throw "Error: Creation of certificate failed."
}

$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $CertificateFileExportPath -Password $pwd -Force | Out-Null
if (Test-Path -Path $CertificateFileExportPath) {
  Write-Host "Certificate ($CertificateFileExportPath) exported successfully." 
}
else {
  throw "Error: Export of certificate failed."
}

