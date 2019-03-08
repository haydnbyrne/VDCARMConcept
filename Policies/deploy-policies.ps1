#Sign in to Azure before running script
Import-Module -Name AzureRM.Resources
$TenantID = (get-azurermcontext).tenant.id
$pathtoscript = "C:\Repos\VDCARM\VDCARMConcept\Policies\" #Change to $PSScriptRoot

$OrgAcronym = "IAG"
#Check Azure sign in
$AzureContext = Get-AzureRmContext
Write-Output "Currently Connected to subscription [$($AzureContext.Subscription.Name)], and AAD Tenant[$($azurecontext.tenant.Directory)]"
Pause

<#---Prerequisites
Do this: https://docs.microsoft.com/en-us/azure/role-based-access-control/elevate-access-global-admin
Then, go to Azure Portal > Management Groups, cliuck "Start using Management Groups" - this creates the root management group
#>

#--------------------Create Subscription Level RBAC Groups
Connect-AzureAD -TenantId $TenantID
New-AzureADGroup -DisplayName "RBAC Read all Azure subscriptions" -MailEnabled $false -SecurityEnabled $true -MailNickName "notset"
New-AzureADGroup -DisplayName "RBAC Owner all Azure subscriptions" -MailEnabled $false -SecurityEnabled $true -MailNickName "notset"

#--------------------Create Management Group Structure
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

$parent = Get-AzureRmManagementGroup |Where-Object {$_.DisplayName -eq "Tenant Root Group"}

$mgmtGroup_Production = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Production" -ParentManagemnentGroup $Parent.id
$mgmtGroup_Production_Internal = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Production_Internal" -ParentManagemnentGroup $mgmtGroup_Production.id
$mgmtGroup_Production_External = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Production_External" -ParentManagemnentGroup $mgmtGroup_Production.id

$mgmtGroup_Development = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Development" -ParentManagemnentGroup $Parent.id
$mgmtGroup_Development_Internal = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Development_Internal" -ParentManagemnentGroup $mgmtGroup_Development.id
$mgmtGroup_Development_External = CreateMgmtgroup -ManagementGroupName "$($OrgAcronym)_Development_External" -ParentManagemnentGroup $mgmtGroup_Development.id

#--------------------Assign RBAC Groups to Management Group Hierarchy
#Top Level (Tenant Root Group) - Note This permissions will flow down through the entire Management Group Hierarchy
$mgmtGroup = Get-AzureRmManagementGroup |Where-Object {$_.DisplayName -eq "Tenant Root Group"}

$group = Get-AzureADGroup |Where-Object {$_.DisplayName -eq "SEC_AZURE_SUBSCRIPTION_READER"}
New-AzureRmRoleAssignment -Scope $mgmtgroup.id -ObjectId $group.objectid -RoleDefinitionName "Reader"

$group = Get-AzureADGroup |Where-Object {$_.DisplayName -eq "SEC_AZURE_SUBSCRIPTION_OWNER"}
New-AzureRmRoleAssignment -Scope $mgmtgroup.id -ObjectId $group.objectid -RoleDefinitionName "Owner"

#--------------------Create Custom Policies
#$controlResourceType = New-AzureRmPolicyDefinition -Description "Audit or Deny a specified list of resource types" -Mode All -Name "ControlResourceType" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\controlresourcetype.json" -Parameter "$($pathtoscript)Policies\controlresourcetype.parameters.json" -DisplayName "Control Resource Types"
New-AzureRmPolicyDefinition -Description "Audit or Deny tag values" -Mode Indexed -Name "ControlTagValue" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\auditdenytagvalue.json" -Parameter "$($pathtoscript)Policies\auditdenytagvalue.parameters.json" -DisplayName "Audit or Deny Tag Value"
New-AzureRmPolicyDefinition -Description "Deny creation of VMs with  non-Managed disks" -Mode All -Name "DenyNonManagedDisks" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\denynonmanageddisks.json" -DisplayName "Deny Creation of VMs with non-Managed Disks"
New-AzureRmPolicyDefinition -Description "Deny creation of VMs without Hybrid Use Benefit Enabled" -Mode All -Name "DenyNonHUB" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\enforceHybridUseBenefit.json" -DisplayName "Deny creation of VMs without Hybrid Use Benefit Enabled"
New-AzureRmPolicyDefinition -Description "Deploy Microsoft Monitoring Agent extension to all Windows VMs" -Mode All -Name "DeployWinVMMMAExt" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\deploy-oms-vm-extension-windows-vm.json" -Parameter "$($pathtoscript)Policies\deploy-oms-vm-extension-windows-vm.parameters.json" -DisplayName "Deploy Microsoft Monitoring Agent extension to all Windows VMs"

#--------------------Assign policies
$AllPolicyDefinitions = Get-AzureRmPolicyDefinition

################BASELINE 
$PolicyScope = "/providers/Microsoft.Management/managementGroups/$($TenantID)"
####SECURITY
#"IAG Baseline - Allowed Locations" - only allow Australian regions
$AllowedLocations = Get-AzureRmLocation | Where-Object {$_.Location -match "australia.*"}
$PolicyParameters = @{'listOfAllowedLocations'=($AllowedLocations.location)}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Allowed Locations"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allowed Locations" -Name "BL-Locations" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Allowed locations for resource groups"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allowed Locations for Resource Groups" -Name "BL-RGLocations" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters


#SQL Encryption
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Audit Transparent Data Encryption Status"}
New-AzureRmPolicyAssignment -Name "BL-TDE" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition

#Require Blob encryption for storage accounts
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Require Blob encryption for storage accounts"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Require Blob encryption for storage accounts" -Name "BL-BlobEncryption" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition

#[Preview]: Deploy default Microsoft IaaSAntimalware extension for Windows Server

#Audit secure transfer to storage accounts


####CONFIGURATION
#Deny VMs that do not use managed disks
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Deny Creation of VMs with non-Managed Disks"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Require Managed Disks for VMs" -Name "BL-VMManagedDisks" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition

#Enforce Hybrid Use Benefit (Cost savings)
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Deny creation of VMs without Hybrid Use Benefit Enabled"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Require Hybrid Use Benefit to be enabled for VMs" -Name "BL-VMHUB" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition


#Enforce Tagging - Enforce tag and its value , Apply tag and its default value, Apply tag and its default value to resource groups, Enforce tag and its value on resource groups
#Tagging initiative
$taggingInitiative = Get-Content -Path "$pathtoscript\policies\tagginginitiative.json" |ConvertFrom-Json
$createTagPolicy = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Apply tag and its default value"}
$auditDenyTagValuePolicy = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Audit or Deny Tag Value"}
foreach ($policydefinition in $taggingInitiative) {
    if ($policydefinition.policydefinitionid -eq "<createtagpolicy>") {$policydefinition.policydefinitionid = $createTagPolicy.policydefinitionid}
    if ($policydefinition.policydefinitionid -eq "<auditdenytagvaluepolicy>") {$policydefinition.policydefinitionid = $auditDenyTagValuePolicy.policydefinitionid}
}
$taggingInitiative = $taggingInitiative | ConvertTo-Json -Depth 20

$taggingdefinition = New-AzureRmPolicySetDefinition -Name "BL-TagInitiative" -Description "Baseline Tagging initiative" -PolicyDefinition $taggingInitiative -ManagementGroupName $TenantID
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Tagging Initiative" -Name "BL-Tagging" -Scope $PolicyScope -PolicySetDefinition $taggingDefinition

#Install required extensions on all VMs. These include IaaS Anti Malware, and the Microsoft Monitoring Agent.
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Deploy Microsoft Monitoring Agent extension to all Windows VMs"}
$PolicyParameters = @{'logAnalytics'="LA-HUB";'proxyUri'="124.47.159.20:8080"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Require Microsoft Monitoring Agent extension for all Window VMs" -Name "BL-VMMMAext" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters -AssignIdentity -Location "Australia East"

#Not allowed resource types, Allowed resource types
#https://servicetrust.microsoft.com/ViewPage/Australia

<#Generate List of all Resource Types
$RTList= @()
$allRPs = Get-AzureRmResourceProvider -ListAvailable # | Where {$_.ProviderNamespace -eq "Microsoft.Network"}
foreach ($RP in $allRPs){
    $RT = $RP.ResourceTypes | Where-Object {!([string]::IsNullOrEmpty($_.Locations))}
    foreach ($y in $RT) {
        $RTList += "$($RP.ProviderNamespace)/$($y.ResourceTypeName)"
    }
}
$RTList 
#>
$ResourceTypeCSV = "$pathtoscript\AllowedResourceTypePolicy.csv"
$ResourceTypeData = Import-Csv -Path $ResourceTypeCSV

$ResourceTypesPROTECTED = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "PROTECTED" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesUDLM = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "UDLM" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesCORE = ($ResourceTypeData | Where-Object {$_.CERTIFICATION -eq "CORE" -and $_.ENABLED -eq "TRUE"}).ResourceType
$ResourceTypesCUSTOMERENABLE = ($ResourceTypeData | Where-Object {[string]::IsNullOrEmpty($_.CERTIFICATION) -and $_.ENABLED -eq "TRUE"}).ResourceType

$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Allowed Resource Types"}

$PolicyScope = $mgmtGroup_Production_Internal.id
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow PROTECTED Resource Types" -Name "BL-PrdPROTECTED" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

$PolicyScope = $mgmtGroup_Production_External.id
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesUDLM + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow UDLM Resource Types" -Name "BL-PrdUDLM" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

$PolicyScope = $mgmtGroup_Development_Internal.id
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow PROTECTED Resource Types" -Name "BL-PrdPROTECTED" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

$PolicyScope = $mgmtGroup_Development_External.id
$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCORE + $ResourceTypesUDLM + $ResourceTypesPROTECTED)}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow UDLM Resource Types" -Name "BL-PrdUDLM" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters


#$PolicyParameters = @{'listOfResourceTypesAllowed'=($ResourceTypesCUSTOMERENABLE + $ResourceTypesCORE + $ResourceTypesUDLM + $ResourceTypesPROTECTED)}
#New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allow CUSTOMER ENABLED Resource Types" -Name "BL-TypeCUSTOMER" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#Allowed virtual machine SKUs
#prevent using old services VMs

(Get-AzureRmPolicyAssignment -Scope "/providers/Microsoft.Management/managementGroups/6508fbc2-ba0b-4c49-9e52-65af01d4ad17").properties.DisplayName

######## Prod INTERNAL
$PolicyScope = $mgmtGroup_Production_Internal.id
#Prevent Public IPs
$PolicyParameters = @{'listOfResourceTypesNotAllowed'=@("Microsoft.Network/publicIPAddresses")}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Not Allowed Resource Types"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Internal - Prevent Public IP Assignment" -Name "INT-PRDDenyPubIP" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters



########EXTERNAL


#Apply a baseline "Block all Internet NSG" to all subnets?

#Enable Security Center
Get-AzureRmPolicyDefinition