#requires -RunAsAdministrator

Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Common DNS FQDN name to be used .")]
    [string] $DNSCName,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate Password to be used to export the cert.")]
    [string] $CertificateSecret,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate file export path where f.")]
    [string] $CertificateFileExportPath
)

if (-not (Test-Path -Path $CertificateFileExportPath -IsValid))
{
    Write-Host "Error: Invlid path syntax for CertificateFileExportPath variable."
}

if (-not ([IO.Path]::GetExtension($CertificateFileExportPath) -eq '.pfx'))
{
    Write-Host "Error: Invlid syntax for CertificateFileExportPath variable. Extension value in path should end with '.pfx'"
}

# Create a self-signed certificate
$ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $DNSCName
$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $CertificateSecret -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $CertificateFileExportPath -Password $pwd
