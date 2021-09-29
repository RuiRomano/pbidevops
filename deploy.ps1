#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

# Install-Module MicrosoftPowerBIMgmt -MinimumVersion 1.2.1026

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\Modules\PBIDevOps" -Force

$projectPath = "$currentPath\SampleProject"
$configPath = "$currentPath\config.json"

Connect-PowerBIServiceAccount

# Deploy Workspaces
Publish-PBIWorkspaces -configPath $configPath

# Deploy Datasets
Publish-PBIDataSets -configPath $configPath -path "$projectPath\DataSets"

# Rebind Reports locally (Un-Supported)
# Set-PBIReportConnections

# Deploy Reports
# README - The live connected PBIX reports need to be binded to an existent Dataset on powerbi.com - Run tool.FixReportConnections.ps1 to fix the pbix connections
# Optional use the parameter '-filter @("Customer.pbix","Purchases.pbix")' to selectively deploy reports. 
# -- without the '-filter' option the Publish-PBIReports will publish all reports into the service from the Reports folder
# -- Note: the @("","") syntax is how you pass in an array in PowerShell
Publish-PBIReports -configPath $configPath -path "$projectPath\Reports" # -filter @("Customer.pbix")

# Deploy PaginatedReports
# Publish-PBIReports -configPath $configPath -path "$projectPath\PaginatedReports"