#Save-Module -Name AzureRM.ManagementGroups -Path C:\Repos\VDCARM\Policies\modules
#Install-Module -Name AzureRM.ManagementGroups -Scope CurrentUser
Import-Module -Name AzureRM.Resources
$Definition = New-AzureRmPolicyDefinition -DisplayName "IAG Allowed Locations" -Name "IAGAllowedLocations" -Description "Only allow deployment of resources in specified regions" -Policy .\Policies\allowedlocations.json
#New-AzureRmPolicyAssignment -PolicyDefinition $Definition -Scope