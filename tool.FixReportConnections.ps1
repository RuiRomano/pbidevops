#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" } -Assembly System.IO.Compression

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Import-Module "$currentPath\modules\PBIDevOps" -Force

$workingDir = "$currentPath\_temp\fixconnections"
$backupdir = "$currentPath\_temp\fixconnections\bkup"
$reportsPath = "$currentPath\SampleProject\Reports"
$configPath = "$currentPath\config-dev.json"
$sharedDatasetsPath = "$currentPath\shareddatasets.json"

Connect-PowerBIServiceAccount

Set-PBIReportConnections -path $reportsPath -configPath $configPath -backupDir $backupdir -workingDir $workingDir -sharedDatasetsPath $sharedDatasetsPath