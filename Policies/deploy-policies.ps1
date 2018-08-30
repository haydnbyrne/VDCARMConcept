Import-Module -Name AzureRM.Resources
$TenantID = (get-azurermcontext).tenant.id
$pathtoscript = "C:\Repos\VDCARM\VDCARMConcept\Policies\"

$OrgAcronym = "IAG"

#--------------------Create Subscription Level RBAC Groups
Connect-AzureAD -TenantId $TenantID
New-AzureADGroup -DisplayName "RBAC Read all Azure subscriptions" -MailEnabled $false -SecurityEnabled $true -MailNickName "notset"
New-AzureADGroup -DisplayName "RBAC Owner all Azure subscriptions" -MailEnabled $false -SecurityEnabled $true -MailNickName "notset"

#--------------------Create Management Group Structure
$parent = Get-AzureRmManagementGroup |Where-Object {$_.DisplayName -eq "Tenant Root Group"}

$mgmtGroup_Production = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Production" -GroupName "$($OrgAcronym)_Production" -ParentId $parent.id
$mgmtGroup_Production_Internal = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Production_Internal" -GroupName "$($OrgAcronym)_Production_Internal" -ParentId $mgmtGroup_Production.id
$mgmtGroup_Production_External = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Production_External" -GroupName "$($OrgAcronym)_Production_External" -ParentId $mgmtGroup_Production.id

$mgmtGroup_Development = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Development" -GroupName "$($OrgAcronym)_Development" -ParentId $parent.id
$mgmtGroup_Development_Internal = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Development_Internal" -GroupName "$($OrgAcronym)_Development_Internal" -ParentId $mgmtGroup_Development.id
$mgmtGroup_Development_External = New-AzureRmManagementGroup -DisplayName "$($OrgAcronym)_Development_External" -GroupName "$($OrgAcronym)_Development_External" -ParentId $mgmtGroup_Development.id

#--------------------Assign RBAC Groups to Management Group Hierarchy
#Top Level (Tenant Root Group) - Note This permissions will flow down through the entire Management Group Hierarchy
$mgmtGroup = Get-AzureRmManagementGroup |Where-Object {$_.DisplayName -eq "Tenant Root Group"}

$group = Get-AzureADGroup |Where-Object {$_.DisplayName -eq "RBAC Read all Azure subscriptions"}
New-AzureRmRoleAssignment -Scope $mgmtgroup.id -ObjectId $group.objectid -RoleDefinitionName "Reader"

$group = Get-AzureADGroup |Where-Object {$_.DisplayName -eq "RBAC Owner all Azure subscriptions"}
New-AzureRmRoleAssignment -Scope $mgmtgroup.id -ObjectId $group.objectid -RoleDefinitionName "Owner"

#--------------------Create Custom Policies
#$controlResourceType = New-AzureRmPolicyDefinition -Description "Audit or Deny a specified list of resource types" -Mode All -Name "ControlResourceType" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\controlresourcetype.json" -Parameter "$($pathtoscript)Policies\controlresourcetype.parameters.json" -DisplayName "Control Resource Types"
New-AzureRmPolicyDefinition -Description "Audit or Deny tag values" -Mode Indexed -Name "ControlTagValue" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\auditdenytagvalue.json" -Parameter "$($pathtoscript)Policies\auditdenytagvalue.parameters.json" -DisplayName "Audit or Deny Tag Value"
New-AzureRmPolicyDefinition -Description "Deny creation ofVMs with  non-Managed disks" -Mode Indexed -Name "DenyNonManagedDisks" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\denynonmanageddisks.json" -DisplayName "Deny Creation of VMs with non-Managed Disks"
New-AzureRmPolicyDefinition -Description "Deny creation of VMs without Hybrid Use Benefit Enabled" -Mode Indexed -Name "DenyNonHUB" -ManagementGroupName $TenantID -Policy "$($pathtoscript)Policies\enforceHybridUseBenefit.json" -DisplayName "Deny creation of VMs without Hybrid Use Benefit Enabled"

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
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Allowed Locations for Resource Groups" -Name "BL-LocationsRG" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#AllowedResourceTypes - only protected-certified services? - audit non-certified?

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
<#
SECCLASS
COSTID
RESOURCEID
OWNER
NEXTREVIEW
Lifecycle
#>

#Array of Tags
$tags = @()
$tags += @{
    "name"="CostID"
    "values"=@()
    "effect"="audit"
}
$tags += @{
    "name"="ResourceID"
    "values"=@("xyz","abc")
    "effect"=""
}
$tags += @{
    "name"="SECCLASS"
    "values"=@("Unclassified-DLM","PROTECTED")
    "effect"="audit"
}

foreach ($tag in $tags) {
    #Create tag if it doesn't exist
    $PolicyParameters = @{'tagName'=$tag.name;'tagValue'="NOTCONFIGURED"}
    $PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Apply tag and its default value"}
    New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Apply $($tag.name) tag and its default value" -Name "BL-Tag$($tag.name)" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

    #tag enforcement
    if (($tag.effect = "audit") -or ($tag.effect = "deny")){
        $PolicyParameters = @{'tagName'=$tag.name;'allowedValues'=$tag.values;'policyEffect'=$tag.effect}
        $PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Audit or Deny Tag Value"}
        New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - $($tag.name) Tag $($tag.effect) Values" -Name "BL-Tag$($tag.name)" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters
    }
}

#create missing tags with a default value
$PolicyParameters = @{'tagName'="COSTID";'tagValue'="NOTCONFIGURED"}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Apply tag and its default value"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Apply tag and its default value" -Name "BL-ResourceTagging" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#Enforce  Tag Value
#$costIDList += '"Programme Office and Deregulation (733)"'
#$costIDList += '"IAG Enterprise Reporting Platform (B96)"'
#$costIDList += '"Cloud Services ASR (D-321-12535-C85)"'
#$costIDList += '"IPP Project (B73)"'

$PolicyParameters = @{'tagName'="COSTID";'allowedValues'=@("BLAH","SOMETHING");'policyEffect'="audit"}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Audit Tag Value"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Baseline - Audit Tag Values" -Name "BL-ResourceTagAudit" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters

#Test
#New-AzureRmStorageAccount -Name "junk998sju2" -ResourceGroupName "JunkNOTAG" -SkuName "Standard_LRS" -Location "Australia East"

#Not allowed resource types, Allowed resource types

#Allowed virtual machine SKUs

(Get-AzureRmPolicyAssignment -Scope "/providers/Microsoft.Management/managementGroups/6508fbc2-ba0b-4c49-9e52-65af01d4ad17").properties.DisplayName

########INTERNAL
$PolicyScope = "/providers/Microsoft.Management/managementGroups/MgmtGroup1"
#Prevent Public IPs
$PolicyParameters = @{'listOfResourceTypesNotAllowed'=@("Microsoft.Network/publicIPAddresses")}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Not Allowed Resource Types"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym Internal - Prevent Public IP Assignment" -Name "INT-DenyPublicIP" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters



########EXTERNAL
#Audit External IPs - disable - if audit conditions are met it counts as a non-compliance
<#
$PolicyParameters = @{'listOfResourceTypes'=@("Microsoft.Network/publicIPAddresses");'policyEffect'="audit"}
$PolicyDefinition = $AllPolicyDefinitions | Where-Object {$_.Properties.DisplayName -eq "Control Resource Types"}
New-AzureRmPolicyAssignment -DisplayName "$OrgAcronym External - Audit Public IP Assignment" -Name "INT-AuditPublicIP" -Scope $PolicyScope -PolicyDefinition $PolicyDefinition -PolicyParameterObject $PolicyParameters
#>

#Apply a baseline "Block all Internet NSG" to all subnets?