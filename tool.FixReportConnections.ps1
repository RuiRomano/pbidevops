#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" } -Assembly System.IO.Compression

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Import-Module "$currentPath\modules\PBIDevOps" -Force

$configPath = "$currentPath\config-dev.json"
$reportsPath = "$currentPath\SampleProject\Reports"
$workingDir = "$currentPath\_temp\fixconnections"
$backupdir = "$currentPath\_temp\fixconnections\bkup"
$sharedDatasetsPath = "$currentPath\shareddatasets.json"

Connect-PowerBIServiceAccount

Set-PBIReportConnections -path $reportsPath -configPath $configPath -backupDir $backupdir -workingDir $workingDir -sharedDatasetsPath $sharedDatasetsPath