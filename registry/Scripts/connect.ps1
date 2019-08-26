$FQDN=""
$TENANT_NAME = ""
$SUBSCRIPTION = ""

# Connect
Add-AzureRMEnvironment -Name "AzureStackTenant" -ArmEndpoint "https://management.$FQDN"

$AuthEndpoint = (Get-AzureRmEnvironment -Name "AzureStackTenant").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($TENANT_NAME)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]
Add-AzureRmAccount -EnvironmentName "AzureStackTenant" -TenantId $TenantId

Select-AzureRmSubscription -Subscription $SUBSCRIPTION | out-null
