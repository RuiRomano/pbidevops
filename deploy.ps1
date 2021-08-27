#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\Modules\PBIDevOps" -Force

$configPath = "$currentPath\config-prd.json"
$credentialsConfigPath = "$currentPath\config.credentials.json"

$credentialsConfig = Get-Content $credentialsConfigPath | ConvertFrom-Json

$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentialsConfig.appId, ($credentialsConfig.appSecret | ConvertTo-SecureString -AsPlainText -Force)

Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $credentialsConfig.tenantId -Credential $credential

# Deploy Workspaces

Publish-PBIWorkspaces -configPath $configPath

# Deploy Datasets

Publish-PBIDataSets -configPath $configPath -path "$currentPath\SampleProject\DataSets"

# Deploy Reports

Publish-PBIReports -configPath $configPath -path "$currentPath\SampleProject\Reports"