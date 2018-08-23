Import-Module -Name AzureRM.Resources
$Definition = New-AzureRmPolicyDefinition -DisplayName "IAG Allowed Locations" -Name "IAGAllowedLocations" -Description "Only allow deployment of resources in specified regions" -Policy "$($PSScriptRoot)Policies\allowedlocations.json"
#New-AzureRmPolicyAssignment -PolicyDefinition $Definition -Scope
Get-AzureRmPolicyAssignment
