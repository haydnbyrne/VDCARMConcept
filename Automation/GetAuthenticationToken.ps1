$IAGAutomationTriggerAppID = "1a6ef61c-c9f4-4e50-90d6-99fe892dc6fa"
$IAGAutomationTriggerKey = "N4hqYHRnX6X/b2qzu6IpBgjsP4+dukC/gmJ3bmu8xdI="
$IAGTenantID = "b3712af2-6728-4e11-bcea-c85236845f55"

#Azure Authtentication Token
#SPN ClientId and Secret
$ClientID       = $IAGAutomationTriggerAppID #ApplicationID
$ClientSecret   = $IAGAutomationTriggerKey  #key from Application
$tenantid      = $IAGTenantID
 

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

$token | select access_token, @{L='Expires';E={[timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($_.expires_on))}} | fl *