# Create a self-signed certificate
$PASSWORD=""
$CN=""
$PATH=""

$ssc = New-SelfSignedCertificate -certstorelocation cert:\LocalMachine\My -dnsname $CN
$crt = "cert:\localMachine\my\" + $ssc.Thumbprint
$pwd = ConvertTo-SecureString -String $PASSWORD -Force -AsPlainText
Export-PfxCertificate -cert $crt -FilePath $PATH -Password $pwd
