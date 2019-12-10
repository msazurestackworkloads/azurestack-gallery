#requires -runasadministrator
<#
.Synopsis
  The script provide functionality to create self signed certificate.

.Description
  The script provide functionality to create self signed certificate.

.Parameter CertificateCN
  Fully qualified domain name to create FQDN specific certificate.

.Parameter CertificatePassword
  Certificate Password to be used to export the cert.

.Parameter CertificateFileExportPath
  Certificate file export path including certificate filename.

.Example
   Self-Signed.ps1 -CertificateCN "registry.local.microsoft.com" 
                   -CertificatePassword <Secret>
                   -CertificateFileExportPath c:\certificate\registry_cert.pfx
#>
Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Fully qualified domain name to create FQDN specific certificate.")]
    [string] $CertificateCN,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate Password to be used to export the cert.")]
    [string] $CertificatePassword,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate file export path including certificate filename.")]
    [string] $CertificateFileExportPath
)

if (-not (Test-Path -Path $CertificateFileExportPath -IsValid))
{
    throw "Error: CertificateFileExportPath is not a valid path."
}

if (-not ([IO.Path]::GetExtension($CertificateFileExportPath) -eq '.pfx'))
{
    throw "Error: Invalid syntax for CertificateFileExportPath variable. Extension value in path should end with '.pfx'"
}

# Create a self-signed certificate
$ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $CertificateCN
$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $CertificateFileExportPath -Password $pwd
