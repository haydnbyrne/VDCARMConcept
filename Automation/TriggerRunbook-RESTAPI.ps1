#region variables
$ClientID       = "1a6ef61c-c9f4-4e50-90d6-99fe892dc6fa" #ApplicationID
$ClientSecret   = "N4hqYHRnX6X/b2qzu6IpBgjsP4+dukC/gmJ3bmu8xdI="  #key from Application
$tenantid      = "b3712af2-6728-4e11-bcea-c85236845f55"
$SubscriptionId = "cb531463-cc30-48a5-8584-61ade0810463"
$resourcegroupname = 'rg_auto_hub'
$AutomationAccountName = 'auto-ause-hub'
$RunbookName = 'HelloWorld'
$APIVersion = '2015-10-31'
#endregion

#region Get Access Token
$TokenEndpoint = {https://login.windows.net/{0}/oauth2/token} -f $tenantid 
$ARMResource = "https://management.core.windows.net/";

$Body = @{
        'resource'= $ARMResource
        'client_id' = $ClientID
        'grant_type' = 'client_credentials'
        'client_secret' = $ClientSecret
}

$params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers = @{'accept'='application/json'}
    Body = $Body
    Method = 'Post'
    URI = $TokenEndpoint
}

$token = Invoke-RestMethod @params
#endregion


#region get Runbooks
$Uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/runbooks?api-version={3}' -f $SubscriptionId, $resourcegroupname, $AutomationAccountName, $APIVersion
$params = @{
  ContentType = 'application/x-www-form-urlencoded'
  Headers     = @{
    'authorization' = "Bearer $($token.Access_Token)"
  }
  Method      = 'Get'
  URI         = $Uri
}
Invoke-RestMethod @params -OutVariable Runbooks
#endregion

#region Start Runbook
$Uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/jobs/{3}?api-version={4}' -f $SubscriptionId, $resourcegroupname, $AutomationAccountName, $((New-Guid).guid), $APIVersion
$body = @{
  'properties' = @{
    'runbook'  = @{
      'name' = $RunbookName
    }
    'parameters' = @{
      'TestParameter' = 'This text was passed in as a parameter'
    }
  }
  'tags'     = @{}
} | ConvertTo-Json
$body

$params = @{
  ContentType = 'application/json'
  Headers     = @{
    'authorization' = "Bearer $($token.Access_Token)"
  }
  Method      = 'Put'
  URI         = $Uri
  Body        = $body
}

Invoke-RestMethod @params -OutVariable Runbook
$Runbook.properties
#endregion

#region get Runbook Status
$Uri ='https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/Jobs/{3}?api-version=2015-10-31' -f $SubscriptionId, $resourcegroupname, $AutomationAccountName, $($Runbook.properties.jobId)
$params = @{
  ContentType = 'application/application-json'
  Headers     = @{
    'authorization' = "Bearer $($token.Access_Token)"
  }
  Method      = 'Get'
  URI         = $Uri
}
Invoke-RestMethod @params -OutVariable Status
$Status.properties
#endregion