$uri = 'https://s8events.azure-automation.net/webhooks?token=CfScRid%2fE7MGkZ%2bdKn0C7rVn7smtEXeMjeE4L2QoFrY%3d'
Invoke-RestMethod -Method POST -Uri $uri #-Body ($request | ConvertTo-Json)
