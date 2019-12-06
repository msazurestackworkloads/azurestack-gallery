#requires -runasadministrator

Param
(
    [Parameter(Mandatory = $true, HelpMessage = "Location of Azure Stack.")]
    [string] $Location,
    [Parameter(Mandatory = $false, HelpMessage = "")]
    [string] $PublisherName = "microsoft-aks",
    [Parameter(Mandatory = $false, HelpMessage = "")]
    [string] $Offer = "aks"
)
{
    Get-AzureRmVMImageSku -Location $Location -PublisherName $PublisherName -Offer $Offer | Select-Object Skus
}