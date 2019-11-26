#requires -RunAsAdministrator

# Password and Common Name of the certificate
$PASSWORD=""
$CN=""
# Export path of the certificate
$PATH=""

# Create a self-signed certificate
$ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $CN
$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $PASSWORD -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $PATH -Password $pwd
