#requires -RunAsAdministrator

Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Certificate fully qualified domain name.")]
    [string] $CertificateCN,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate Password to be used to export the cert.")]
    [string] $CertificateSecret,
    [Parameter(Mandatory = $true, HelpMessage = "Certificate file export path including certificate filename.")]
    [string] $CertificateFileExportPath
)

if (-not (Test-Path -Path $CertificateFileExportPath -IsValid))
{
    Write-Host "Error: CertificateFileExportPath is not a valid path."
}

if (-not ([IO.Path]::GetExtension($CertificateFileExportPath) -eq '.pfx'))
{
    Write-Host "Error: Invalid syntax for CertificateFileExportPath variable. Extension value in path should end with '.pfx'"
}

# Create a self-signed certificate
$ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $CertificateCN
$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $CertificateSecret -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $CertificateFileExportPath -Password $pwd
