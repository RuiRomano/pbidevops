#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

# Install-Module MicrosoftPowerBIMgmt -MinimumVersion 1.2.1026

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\Modules\PBIDevOps" -Force

$projectPath = "$currentPath\SampleProject"
$configPath = "$currentPath\config.json"

try {
    
    $token = try { Get-PowerBIAccessToken -AsString } catch {}

    if (!$token)
    {
        Connect-PowerBIServiceAccount
    }

    # Deploy Workspaces

    Publish-PBIWorkspaces -configPath $configPath

    # Deploy Datasets

    Publish-PBIDataSets -configPath $configPath -path "$projectPath\DataSets"

    # Deploy Reports
    # README - The live connected PBIX reports need to be binded to an existent Dataset on powerbi.com - Run tool.FixReportConnections.ps1 to fix the pbix connections
    Publish-PBIReports -configPath $configPath -path "$projectPath\Reports"

    # Deploy PaginatedReports (Requires Premium Workspace)

    Publish-PBIReports -configPath $configPath -path "$projectPath\PaginatedReports"
}
catch {
    $exception = $_.Exception

    if ($exception.Response)
    {
        Write-Error "PBI API Error Details: '$($exception.Response.Content)'" -Exception $exception
    }

    throw
}
