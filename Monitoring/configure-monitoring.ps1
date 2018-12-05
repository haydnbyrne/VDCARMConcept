
#Note - select subscription where workspace is to be created

$ResourceGroup = "JUNK-PMC-oms"
$WorkspaceName = "PMC-log-analytics-34099" # workspace names need to be unique - Get-Random helps with this for the example code
$Location = "australiasoutheast"
$retentionindays = 400

# Create the resource group if needed
try {
    Get-AzureRmResourceGroup -Name $ResourceGroup -ErrorAction Stop
} catch {
    New-AzureRmResourceGroup -Name $ResourceGroup -Location $Location
}

# Create the workspace
New-AzureRmOperationalInsightsWorkspace -Location $Location -Name $WorkspaceName -sku StandAlone -ResourceGroupName $ResourceGroup -RetentionInDays $retentionindays

###-ADD DATA SOURCES
# Add Activity Logs for all subscriptions
$subscriptions = get-azurermsubscription

$workspace = Get-AzureRmOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroup
New-AzureRmOperationalInsightsAzureActivityLogDataSource -Workspace $Workspace -Name "OMSDataSource-MSDN3-ActivityLogs" -SubscriptionId 7c4312e2-ea81-4518-b241-66972fdc4fae

#Add Azure AD Diagnosticv logs
#Can't find powershell cmdlet to do this :()

#list all solutions
Get-AzureRmOperationalInsightsIntelligencePacks -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName

#Enable Activity Logs solution
Set-AzureRmOperationalInsightsIntelligencePack -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -IntelligencePackName "AzureActivity" -Enabled $true

#Log Analytics RBAC Groups

########################
#Enable Security Center cmdlets - NOTE: This module is in PREVIEW 
Install-Module -Name AzureRM.Security -AllowPrerelease -Scope CurrentUser
Import-module  AzureRM.Security

#Enable Security Policy for each subscription
    #Pricing Tier - Free or Standard. For Standard choosefrom  VMs, SQL and APP Services
    Set-AzureRmSecurityPricing -Name "default" -PricingTier "Free"

    #Data Collection - Specify Log Analytics Workspace, Raw Data. Configure Auto Agent provisioning
    $workspace = Get-AzureRmOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroup
    Set-AzureRmSecurityWorkspaceSetting -Name "default" -Scope "/subscriptions/$((Get-AzureRMContext).Subscription.ID)" -WorkspaceId $workspace.ResourceId
    Set-AzureRmSecurityAutoProvisioningSetting -Name "default" -EnableAutoProvision

    #Threat Detection - enable Defencer ATP, Cloud App Security
    #Email Notifications - email, phone, settings
    Set-AzureRmSecurityContact -Name "default1" -Email "CISO@my-org.com" -Phone "2142754038" -AlertsAdmin -NotifyOnAlert 


#Add Azure AD Identity Protection Security SOlution

#Set up a diagnostics storage account/s
#for VM diag and boot lgs