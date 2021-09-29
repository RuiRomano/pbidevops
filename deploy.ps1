#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\Modules\PBIDevOps" -Force

$configPath = "$currentPath\config-prd.json"

Connect-PowerBIServiceAccount

# Deploy Workspaces

Publish-PBIWorkspaces -configPath $configPath

# Deploy Datasets

Publish-PBIDataSets -configPath $configPath -path "$currentPath\SampleProject\DataSets"

# Deploy Reports

Publish-PBIReports -configPath $configPath -path "$currentPath\SampleProject\Reports"