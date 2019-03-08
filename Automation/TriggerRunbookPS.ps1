Add-AzAccount -identity
Start-AzAutomationRunbook -Name "HelloWorld" -AutomationAccountName "auto-ause-hub" -ResourceGroupName "rg_auto_hub" -Parameters @{"testparameter"="blah blha blha"}