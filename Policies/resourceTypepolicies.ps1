$OrgName = "Contoso"
$ResourceTypeCSV = "$PSScriptRoot\AllowedResourceTypePolicy.csv"

#Create Management Groups - create a structure that suits your customer - The example structure below creates management groups to align to security requirements.
Function CreateMgmtgroup {
    Param (
        $ManagementGroupName,
        $ParentManagemnentGroup
        )

    $MgmtGroup = Get-AzureRmManagementGroup -GroupName $ManagementGroupName -ErrorAction SilentlyContinue
    if (!$MgmtGroup) {
        $MgmtGroup = New-AzureRmManagementGroup -DisplayName $ManagementGroupName -GroupName $ManagementGroupName -ParentId $ParentManagemnentGroup
    }
    Return $MgmtGroup
}
$RootManagementGroup = Get-AzureRmManagementGroup |Where-Object {$_.DisplayName -eq "Tenant Root Group"}
$UDLMManagementGroup = CreateMgmtgroup -ManagementGroupName "$($OrgName)_UDLM" -ParentManagemnentGroup $RootManagementGroup.id
$PROTECTEDManagementGroup = CreateMgmtgroup -ManagementGroupName "$($OrgName)_PROTECTED" -ParentManagemnentGroup $RootManagementGroup.id
$CUSTOMERManagementGroup = CreateMgmtgroup -ManagementGroupName "$($OrgName)_CUSTOM" -ParentManagemnentGroup $RootManagementGroup.id

#Get CSV file containing all Azure Resource Types and Classification, and compile arrays containing the ResourceTypes for each classification
$ResourceTypeData = Import-Csv -Path $ResourceTypeCSV

$ResourceTypesPROTECTED = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "PROTECTED" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesUDLM = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "UDLM" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesCORE = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "CORE" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesCUSTOMERENABLE = ($ResourceTypeData | Where-Object {[string]::IsNullOrEmpty($_.CERTIFICATION) -and $_.ENABLED -eq "TRUE"}).ResourceType

#--------------------------------
#Apply Policies to Tenant Root Group - these policies will apply to any subscription added to the tenant. Apply "Baseline" policies at this level, they will flow down through the Management Group hierarchy.
#Note: The most restrictive policy will take effect when applied to a Management Group, Subscription or Resource Group - so be careful which policies you apply at the Root level.
$PolicyScope = $RootManagementGroup.Id

#Restrict Regions - only Allow Australian Regions
$AllowedLocations = Get-AzureRmLocation | Where-Object {$_.Location -match "australia.*"}
$PolicyParameters = @{'listOfAllowedLocations'=($AllowedLocations.location)}
$PolicyDefinition = Get-AzureRmPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Allowed Locations"}
New-AzureRmPolicyAssignment -DisplayName "Baseline - Allowed Locations" -Name "BL-Locations" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters
$PolicyDefinition = Get-AzureRmPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Allowed locations for resource groups"}
New-AzureRmPolicyAssignment -DisplayName "Baseline - Allowed Locations for Resource Groups" -Name "BL-LocationsRG" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#List Allowed Resource Types (Any Classification + Customer selected)
$PolicyDefinition = Get-AzureRmPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Allowed Resource Types"}
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCUSTOMERENABLE + $ResourceTypesCORE + $ResourceTypesUDLM + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow CUSTOMER ENABLED Resource Types" -Name "BL-TypeCUSTOMER" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#--------------------------------
#Apply Policies to PROTECTED Management Group - apply policies to assist with PROTECTED compliance
$PolicyScope = $PROTECTEDManagementGroup.Id

#List Allowed Resource Types (Core + Protected ONLY)
$PolicyDefinition = Get-AzureRmPolicyDefinition| Where-Object {$_.Properties.DisplayName -eq "Allowed Resource Types"}
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym PROTECTED - Allow PROTECTED Resource Types" -Name "BL-TypePROTECTED" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#--------------------------------
#Apply Policies to UDLM Management Group - apply policies to assist with UDLM compliance
$PolicyScope = $UDLMManagementGroup.Id

#List Allowed Resource Types (Core + UDLM + Protected ONLY)
$PolicyDefinition = Get-AzureRmPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Allowed Resource Types"}
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesUDLM + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym UDLM - Allow UDLM Resource Types" -Name "BL-TypeUDLM" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters
