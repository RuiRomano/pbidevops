#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

param(
    [string]$path = ".\SampleProject"
    ,
    [string]$configPath = ".\config.json"
    ,
    [bool]$workspaces = $true
    ,
    [bool]$datasets = $true
    ,
    [bool]$reports = $true
    ,
    [bool]$paginatedReports = $false
)


# Install-Module MicrosoftPowerBIMgmt -MinimumVersion 1.2.1026

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\Modules\PBIDevOps" -Force

Connect-PowerBIServiceAccount


if ($workspaces)
{
    Publish-PBIWorkspaces -configPath $configPath
}    

if ($datasets)
{
    Publish-PBIDataSets -configPath $configPath -path "$path\DataSets"
}

# Deploy Reports

if ($reports)
{
    # README - The live connected PBIX reports need to be binded to an existent Dataset on powerbi.com - Run tool.FixReportConnections.ps1 to fix the pbix connections
    Publish-PBIReports -configPath $configPath -path "$path\Reports"
}

if ($paginatedReports)
{    
    Publish-PBIReports -configPath $configPath -path "$path\PaginatedReports"
}
