#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" } -Assembly System.IO.Compression

function Get-EnvironmentMetadata
{
    [CmdletBinding()]
    param
    (
        [string]$configPath
    )

    if (!(Test-Path -Path $configPath))
    {
        throw "Cannot find metadata file '$configPath'"
    }

    Write-Host "##[command]Reading metadata from file: '$configPath'"

    $metadata = Get-Content -Path $configPath  | ConvertFrom-Json

    return $metadata
}

function Get-WorkspaceMetadata
{
    [CmdletBinding()]
    param
    (
        $environmentMetadata,
        $name        
    )

    $metadata = $environmentMetadata.Workspaces.psobject.Properties |? { $_.Name -eq $name } | Select -First 1

    if (!$metadata)
    {
        throw "Cannot find configuration for workspace '$name'"
    }

    if ([string]::IsNullOrEmpty($metadata.Value.WorkspaceId))
    {
        $pbiWorkspaceName = $metadata.Value.WorkspaceName

        if ([string]::IsNullOrEmpty($pbiWorkspaceName))
        {
            $pbiWorkspaceName = $metadata.Name
        }

        #$pbiWorkspace = Get-PBIWorkspace -authToken $authToken -name $pbiWorkspaceName
        $pbiWorkspace = Get-PowerBIWorkspace -Name $pbiWorkspaceName

        if ($pbiWorkspace)
        {
            $metadata.Value | Add-Member -NotePropertyName WorkspaceId -NotePropertyValue $pbiWorkspace.id
            $metadata.Value | Add-Member -NotePropertyName CapacityId -NotePropertyValue $pbiWorkspace.capacityId
        }
        else
        {
            throw "Cannot find Power BI Workspace with name '$pbiWorkspaceName'"
        }
    }


    Write-Output $metadata.Value
}

function Get-DataSetMetadata
{
    [CmdletBinding()]
    param
    (
        $environmentMetadata,
        $name,        
        [switch]$getWorkspaceName
    )

    $metadata = @($environmentMetadata.DataSets.psobject.Properties |? { $_.Name -eq $name } |% { $_.Value })

    if (!$metadata)
    {
        $metadata = $environmentMetadata.DataSets.Default

        if (!$metadata)
        {
            Write-Host "##[error] Cannot find configuration for dataset '$name'"

            return
        }
    }
    
    # Solve other metadata fields if needed
    $metadata |% {

        $item = $_

        if ([string]::IsNullOrEmpty($item.WorkspaceId))
        {
            if (![string]::IsNullOrEmpty($item.Workspace))
            {
                $workspaceMetadata = Get-WorkspaceMetadata -environmentMetadata $environmentMetadata -name $item.Workspace

                $workspaceId = $workspaceMetadata.WorkspaceId
            }
            elseif (![string]::IsNullOrEmpty($item.WorkspaceName))
            {
                #$pbiWorkspace = Get-PBIWorkspace -authToken $authToken -name $item.WorkspaceName
                $pbiWorkspace = Get-PowerBIWorkspace -name $item.WorkspaceName

                if (!$pbiWorkspace)
                {
                    throw "Cannot find Power BI Workspace with name '$($item.WorkspaceName)'"
                }

                $workspaceId = $pbiWorkspace.id
            }

            $item | Add-Member -NotePropertyName WorkspaceId -NotePropertyValue $workspaceId
        }

        if ($getWorkspaceName -and [string]::IsNullOrEmpty($item.WorkspaceName))
        {
            #$pbiWorkspace = Get-PBIWorkspace -authToken $authToken -id $item.WorkspaceId
            $pbiWorkspace = Get-PowerBIWorkspace -id $item.WorkspaceId

            $item | Add-Member -NotePropertyName WorkspaceName -NotePropertyValue $pbiWorkspace.name
        }

        $pbiDataSetName = $item.DataSetName

        if ([string]::IsNullOrEmpty($pbiDataSetName))
        {
            $pbiDataSetName = [System.IO.Path]::GetFileNameWithoutExtension($name)

            $item | Add-Member -NotePropertyName DataSetName -NotePropertyValue $pbiDataSetName
        }

        if ([string]::IsNullOrEmpty($item.DataSetId) -and [string]::IsNullOrEmpty($item.Server))
        {
            #$pbiDataSet = Get-PBIDataSet -authToken $authToken -groupId $item.WorkspaceId -name $pbiDataSetName
            $pbiDataSet = Get-PowerBIDataset -WorkspaceId $item.WorkspaceId -name $pbiDataSetName

            if ($pbiDataSet)
            {
                $item | Add-Member -NotePropertyName DataSetId -NotePropertyValue $pbiDataSet.id
            }
        }

        Write-Output $item
    }

}

function Get-ReportMetadata
{
    [CmdletBinding()]
    param
    (
        $environmentMetadata,
        $filePath        
    )

    $metadata = @($environmentMetadata.Reports.psobject.Properties |? { $filePath -like "*$($_.Name)*" } |% { $_.Value })

    if (!$metadata)
    {
        Write-Host "##[error] Cannot find configuration for report '$filePath'"

        return
    }

    # Solve other metadata fields if needed

    $metadata |% {

        $item = $_

        $reportName = $item.ReportName

        if (!$reportName)
        {
            $reportName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)            
        }

        $item | Add-Member -NotePropertyName ReportName -NotePropertyValue $reportName -Force

        $reportType = "PowerBI"

        if ([System.IO.Path]::GetExtension($filePath) -ieq ".rdl")
        {
            $reportType = "PaginatedReport"            
        }
  
        $item | Add-Member -NotePropertyName ReportType -NotePropertyValue $reportType -Force

        if ([string]::IsNullOrEmpty($item.WorkspaceId))
        {
            if (![string]::IsNullOrEmpty($item.Workspace))
            {
                $workspaceMetadata = Get-WorkspaceMetadata -environmentMetadata $environmentMetadata -name $item.Workspace

                $workspaceId = $workspaceMetadata.WorkspaceId
            }
            elseif (![string]::IsNullOrEmpty($item.WorkspaceName))
            {
                $pbiWorkspace = Get-PowerBIWorkspace -name $item.WorkspaceName

                if (!$pbiWorkspace)
                {
                    throw "Cannot find Power BI Workspace with name '$($item.WorkspaceName)'"
                }

                $workspaceId = $pbiWorkspace.id                
            }

            $item | Add-Member -NotePropertyName WorkspaceId -NotePropertyValue $workspaceId
            
            $item | Add-Member -NotePropertyName WorkspaceMetadata -NotePropertyValue $workspaceMetadata
        }

        if ([string]::IsNullOrEmpty($item.DataSetId))
        {
            $dataSetMetadata = Get-DataSetMetadata -environmentMetadata $environmentMetadata -name $item.DataSet

            if (!$dataSetMetadata)
            {
                throw "Cannot find DataSet configuration '$($item.DataSet)'"
            }

            $item | Add-Member -NotePropertyName DataSetId -NotePropertyValue $dataSetMetadata.DataSetId
        }

        Write-Output $item
    }
}

function Publish-PBIDataSets
{
    [CmdletBinding()]
    param(
        $path
        ,
        $configPath = ""        
        ,
        $deleteDataSetReport = $true
        ,
        $filter = @()
    )
    
    $rootPath = $PSScriptRoot

    if ([string]::IsNullOrEmpty($path))
    {
        $path = "$rootPath\DataSets"
    }

    if ([string]::IsNullOrEmpty($configPath))
    {
        $configPath = "$rootPath\config.json"
    }
   
    Write-Host "##[debug] Publish-PBIDataSets"

    $paramtersStr = ($MyInvocation.MyCommand.Parameters.GetEnumerator() |% {$_.Key + "='$((Get-Variable -Name $_.Key -EA SilentlyContinue).Value)'"}) -join ";"

    Write-Host "##[debug]Parameters: $paramtersStr"

    $datasets = Get-ChildItem -File -Path "$path\*.pbix" -Recurse -ErrorAction SilentlyContinue

    if ($filter -and $filter.Count -gt 0)
    {
        $datasets = $datasets |? { $filter -contains $_.Name }
    }

    if ($datasets.Count -eq 0)
    {
        Write-Host "##[warning] No models to deploy on path '$path'"
        return
    }

    $environmentMetadata = Get-EnvironmentMetadata $configPath

    $datasets |% {

        $modelFile = $_

        $filePath = $modelFile.FullName
        $fileName = $modelFile.Name
        $defaultDatasetName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

        $datasetMetadata = @(Get-DataSetMetadata -environmentMetadata $environmentMetadata -name $fileName)

        if (!$datasetMetadata)
        {
            throw "Cannot find DataSet configuration '$fileName'"
        }

        Write-Host "##[command] Deploying to $($datasetMetadata.Count) locations"

        $datasetMetadata |% {
        
            $targetServer = $_

            $workspaceId = $_.WorkspaceId

            if (![string]::IsNullOrEmpty($targetServer.DataSetName))
            {
                $datasetName = $targetServer.DataSetName
            }
            else
            {
                $datasetName = $defaultDatasetName
            }

            Write-Host "##[group]Deploying Model: '$filePath' to Workspace '$workspaceId'"
        
            Write-Host "##[debug]Publishing '$fileName' to '$datasetName'"

            #$import = Import-PBIFile -authToken $authToken -file $filePath -dataSetName $datasetName -nameConflict CreateOrOverwrite -groupId $workspaceId -wait

            $newDataSet = New-PowerBIReport -Path $filePath -Name $datasetName -ConflictAction CreateOrOverwrite -WorkspaceId $workspaceId

            #$newDataSet = Get-PBIDataSet -authToken $authToken -name $datasetName -groupId $workspaceId            
            $newDataSet = Get-PowerBIDataset -WorkspaceId $workspaceId -Name $datasetName

            if (!$newDataSet)
            {
                throw "Error publishing dataset"
            }

            # Delete the published report of the dataset

            if ($deleteDataSetReport)
            {               
                #$datasetReports = @(Get-PBIReport -authToken $authToken -groupId $workspaceId |? { $_.datasetId -eq $newDataSet.id -and $_.name -eq $datasetName})                
                $datasetReports = @(Get-PowerBIReport -WorkspaceId $workspaceId |? { $_.datasetId -eq $newDataSet.id -and $_.name -eq $datasetName})

                if ($datasetReports.Count -gt 1)
                {
                    Write-Host "##[warning]There is more than 1 report using the published dataset"
                }
                elseif ($datasetReports.Count -eq 1)
                {
                    Write-Host "##[command]Deleting the PBIX Report that comes with the PBIX"

                    #$datasetReports | Remove-PBIReport -authToken $authToken

                    Invoke-PowerBIRestMethod -Url "groups/$workspaceId/reports/$($datasetReports[0].id)" -Method Delete | Out-Null
                }
            }

            if ($targetServer.Parameters)
            {
                $dsParams = $targetServer.Parameters.psobject.properties | foreach -begin {$h=@{}} -process {$h."$($_.Name)" = $_.Value } -end {$h}

                if ($dsParams.Count -ne 0)
                { 
                    Write-Host "##[debug]Take Ownership of DataSet"

                    #Invoke-PBIRequest -authToken $authToken -resource "datasets/$($newDataSet.id)/Default.TakeOver" -groupId $workspaceId -method Post

                    Invoke-PowerBIRestMethod -Url "groups/$workspaceId/datasets/$($newDataSet.id)/Default.TakeOver" -Method Post | Out-Null

                    Write-Host "##[debug]Setting DataSet parameters"

                    #$newDataSet | Set-PBIDatasetParameters -authToken $authToken -groupId $workspaceId -parameters $dsParams
                             
                    $updateDetails = @()

                    @($dsParams.Keys) |% { 
                        $updateDetails += @{
                            "name" = $_
                            ;
                            "newValue" = $dsParams[$_]
                        }
                    }

                    $bodyObj = @{updateDetails=$updateDetails}

                    $bodyStr = $bodyObj | ConvertTo-Json

                    Invoke-PowerBIRestMethod -Url "groups/$workspaceId/datasets/$($newDataSet.id)/UpdateParameters" -Body $bodyStr -Method Post | Out-Null
                }
            }
        
            Write-Host "##[endgroup]"
        }
    }
}

function Publish-PBIReports
{
    [CmdletBinding()]
    param(
        $path 
        ,
        $configPath = ""       
        ,
        $filter = @()
    )

    $rootPath = $PSScriptRoot

    if ([string]::IsNullOrEmpty($path))
    {
        $path = "$rootPath\Reports"
    }

    if ([string]::IsNullOrEmpty($configPath))
    {
        $configPath = "$rootPath\config.json"
    }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "PublishPBIReports_$((New-Guid).ToString("N"))"
    
    New-Item -ItemType Directory -Path $tempPath -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Host "##[debug] Publish-PBIReports"

    $paramtersStr = ($MyInvocation.MyCommand.Parameters.GetEnumerator() |% {$_.Key + "='$((Get-Variable -Name $_.Key -EA SilentlyContinue).Value)'"}) -join ";"

    Write-Host "##[debug]Parameters: $paramtersStr"

    $reports = Get-ChildItem -File -Path $path -Include @("*.pbix", "*.rdl") -Recurse -ErrorAction SilentlyContinue

    if ($filter -and $filter.Count -gt 0)
    {
        $reports = $reports |? { $filter -contains $_.Name }
    }

    if ($reports.Count -eq 0)
    {
        Write-Host "##[warning] No reports to deploy on path '$path'"
        return
    }

    $environmentMetadata = Get-EnvironmentMetadata $configPath

    Write-Host "##[command]Deploying '$($reports.Count)' reports"

    $reports |% {

        $pbixFile = $_

        Write-Host "##[group]Deploying report: '$($pbixFile.Name)'"

        $filePath = $pbixFile.FullName

        $reportsMetadata = @(Get-ReportMetadata -environmentMetadata $environmentMetadata -filePath $filePath)

        if (!$reportsMetadata)
        {
            throw "Cannot find Report configuration '$filePath'"
        }

        try
        {
            foreach($reportMetadata in $reportsMetadata)
            {                        
                $workspaceId = $reportMetadata.WorkspaceId
                $targetDatasetId = $reportMetadata.DataSetId
                $reportName = $reportMetadata.ReportName
                $reportType = $reportMetadata.ReportType

                if ([string]::IsNullOrEmpty($targetDatasetId))
                {
                    throw "Cannot solve target dataset id, make sure its deployed"
                }        

                if ($reportType -ieq "PaginatedReport" -and $reportMetadata.WorkspaceMetadata.CapacityId -eq $null)
                {
                    throw "Cannot deploy Paginated Reports to Non Premium Workspaces"
                }

                $reportNameForUpload = $reportName

                # PaginatedReport upload requires the 'datasetDisplayName' to end with "*.rdl"

                if ($reportType -ieq "PaginatedReport")
                {                    
                    $reportNameForUpload += ".rdl" 
                }            

                if ($reportType -ieq "PaginatedReport")
                {
                    Write-Host "##[command] Rebinding Paginated Report to dataset '$targetDatasetId' by changing the connectionstring on RDL file"
                                        
                    $rdlXml = [xml](Get-Content $filePath)

                    foreach($rdlDatasource in $rdlXml.Report.DataSources.DataSource)
                    {
                        if ($rdlDatasource.ConnectionProperties.DataProvider -ieq "PBIDATASET")
                        {                                         
                            $connStringBuilder = New-Object System.Data.Common.DbConnectionStringBuilder
                            #$connStringBuilder.ConnectionString = $rdlDatasource.ConnectionProperties.ConnectString
                            $connStringBuilder.PSObject.Properties['ConnectionString'].Value = $rdlDatasource.ConnectionProperties.ConnectString

                            $catalog = $connStringBuilder["Initial Catalog"]
                           
                            $newCatalog = "sobe_wowvirtualserver-$targetDatasetId"                            

                            Write-Host "Rebinding datasource: '$($rdlDatasource.DataSourceID)' from '$catalog' to '$newCatalog'"

                            $connStringBuilder["Initial Catalog"] = $newCatalog

                            $rdlDatasource.ConnectionProperties.ConnectString = $connStringBuilder.ConnectionString
                        }
                    }

                    $tempRDLFilePath = Join-Path $tempPath $pbixFile.Name
                    
                    $rdlXml.Save($tempRDLFilePath);
                                        
                    $filePath = $tempRDLFilePath
                }
                  
                Write-Host "##[command] Uploading report '$reportName' into workspace '$workspaceId' and binding to dataset '$targetDatasetId'"

                $targetReport = @(Get-PowerBIReport -WorkspaceId $workspaceId -Name $reportName)

                if ($targetReport.Count -eq 0)
                {
                    Write-Host "##[command] Uploading new report to workspace '$workspaceId'"
                    
                    $importResult = New-PowerBIReport -Path $filePath -WorkspaceId $workspaceId -Name $reportNameForUpload -ConflictAction Abort 
                    
                    $targetReportId = $importResult.Id
                }
                else
                {
                    if ($targetReport.Count -gt 1)
                    {
                        throw "More than one report with name '$reportName'"
                    }

                    Write-Host "##[command] Report already exists on workspace '$workspaceId', uploading to temp report & updatereportcontent"

                    $targetReport = $targetReport[0]

                    $targetReportId = $targetReport.id

                    if ($reportType -ieq "PaginatedReport")
                    {
                        Write-Host "##[command] Overwrite paginated report"

                        $importResult = New-PowerBIReport -Path $filePath -WorkspaceId $workspaceId -Name $reportNameForUpload -ConflictAction Overwrite 
                    }
                    else
                    {
                        # Upload a temp report and update the report content of the target report

                        # README - This is required because of a "bug" of IMport API that always duplicate the report if the dataset is different (may be solved in the future)

                        $tempReportName = "Temp_$([System.Guid]::NewGuid().ToString("N"))"

                        Write-Host "##[command] Uploadind as a temp report '$tempReportName'"
                   
                        $importResult = New-PowerBIReport -Path $filePath -WorkspaceId $workspaceId -Name $tempReportName -ConflictAction Abort
                    
                        $tempReportId = $importResult.Id

                        Write-Host "##[command] Updating report content"
                    
                        $updateContentResult = Invoke-PowerBIRestMethod -method Post -Url "groups/$workspaceId/reports/$targetReportId/UpdateReportContent" -Body (@{
                            sourceType = "ExistingReport"
                            sourceReport = @{
                            sourceReportId = $tempReportId
                            sourceWorkspaceId = $workspaceId
                            }
                        } | ConvertTo-Json)
                
                        # Delete the temp report

                        Write-Host "##[command] Deleting temp report '$tempReportId'"
                         
                        Invoke-PowerBIRestMethod -Method Delete -Url "groups/$workspaceId/reports/$tempReportId" | Out-Null
                    }
                }
                
                if ($reportType -ieq "PaginatedReport")
                {
                    # Rebinding the RDL locally, this way works even when the local rdl is targeting an invalid datasetid
                    
                    # Write-Host "##[command] Rebinding Paginated Report to dataset '$targetDatasetId'"

                    # $paginatedReportDataSources = @(Invoke-PowerBIRestMethod -url "groups/$workspaceId/reports/$targetReportId/datasources" -Method Get | ConvertFrom-Json | Select -ExpandProperty value)

                    # foreach($datasource in $paginatedReportDataSources)
                    # {
                    #     if ($datasource.datasourceType -eq "AnalysisServices" -and $datasource.connectionDetails.server -ilike "pbiazure://*")
                    #     {   
                    #         Write-Host "##[command] Changing RDL Datasource '$($datasource.name)'"
                              
                    #         $bodyObj = @{
                    #             updateDetails=@(
                    #             @{
                    #                 "datasourceName" = $datasource.name
                    #                 ;
                    #                 "connectionDetails" = @{
                    #                     "server" = $datasource.connectionDetails.server
                    #                     ;
                    #                     "database" = "sobe_wowvirtualserver-$targetDatasetId"
                    #                 }
                    #             }
                    #             )
                    #         }

                    #         $bodyStr = $bodyObj | ConvertTo-Json -Depth 5

                    #         Invoke-PowerBIRestMethod -url "groups/$workspaceId/reports/$targetReportId/Default.UpdateDatasources" -Method Post -Body $bodyStr    
                    #     }

                    # }                    
                }
                else
                {
                    if ($targetReportId)
                    {
                        Write-Host "##[command] Rebinding to dataset '$targetDatasetId'"
                        
                        Invoke-PowerBIRestMethod -Method Post -Url "groups/$workspaceId/reports/$targetReportId/Rebind" -Body "{datasetId: '$targetDatasetId'}" | Out-Null
                    }   
                }     
            }

        }
        catch
        {
            $ex = $_.Exception

            if ($_.ErrorDetails.Message -and $_.ErrorDetails.Message.Contains("PowerBIModelNotFoundException"))
            {
               Write-Error -Exception $ex -Message "PBIX is connecting to a nonexistent DataSet or user dont have permission"
            }
            else
            {
                throw
            }
        }

        Write-Host "##[endgroup]"
    }
}


function Publish-PBIWorkspaces
{
    [CmdletBinding()]
    param(
        $configPath = ""
        ,
        $defaultWorkspaceConfigPath = ""                
        ,
        $filter = @()
    )

    $rootPath = $PSScriptRoot

    if ([string]::IsNullOrEmpty($configPath))
    {
        $configPath = "$rootPath\config.json"
    }

    Write-Host "##[debug]Publish-PBIWorkspaces"

    $paramtersStr = ($MyInvocation.MyCommand.Parameters.GetEnumerator() |% {$_.Key + "='$((Get-Variable -Name $_.Key -EA SilentlyContinue).Value)'"}) -join ";"

    Write-Host "##[debug]Parameters: $paramtersStr"

    $environmentMetadata = Get-EnvironmentMetadata -configPath $configPath

    if (!$environmentMetadata)
    {
        Write-Host "##[warning]No configuration found"
        return
    }
    
    if (!$environmentMetadata.Workspaces)
    {
        Write-Host "##[debug]No workspaces configured"
        return
    }

    Write-Host "##[command]Getting Power BI Workspaces"

    $pbiWorkspaces = Get-PowerBIWorkspace -All

    $defaultWorkspaceMetadata = $environmentMetadata.Workspaces.Default

    $workspacesMetadata = @($environmentMetadata.Workspaces.psobject.Properties |? Name -ne "Default")

    $defaultWorkspaceConfig = $null

    if ($defaultWorkspaceConfigPath)
    {
        If (Test-Path $defaultWorkspaceConfigPath)
        {
            $defaultWorkspaceConfig = Get-Content -Path $defaultWorkspaceConfigPath | ConvertFrom-Json
        }
        else
        {
            Write-Host "##[warning]Cannot find default workspace configuration: '$defaultWorkspaceConfigPath'"
        }
    }

    $workspacesMetadata |% {
    
        $workspacePermissions = $_.Value.Permissions
        $capacityId = $_.Value.DedicatedCapacityId
        $capacityName = $_.Value.DedicatedCapacityName
        $workspaceName = $_.Value.WorkspaceName
        $workspaceDeployOptions = $_.Value.DeployOptions

        if ([string]::IsNullOrEmpty($workspaceName))
        {
            $workspaceName = $_.Name
        }

        Write-Host "##[group]Configuring workspace: '$workspaceName'"

        $workspace = $pbiWorkspaces |? name -eq $workspaceName | Select -First 1

        if (!$workspace)
        {              
            $workspace = New-PowerBIWorkspace -name $workspaceName
        }
        else
        {
            Write-Host "##[debug]Workspace '$workspaceName' already exists"
        }    
       
        $workspaceUsers = Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/users" -Method Get | ConvertFrom-Json | Select -ExpandProperty value

        if (!$workspaceDeployOptions -or !$workspaceDeployOptions.IgnoreDefaultPermissions)
        {
            if ($defaultWorkspaceMetadata -and $defaultWorkspaceMetadata.Permissions)
            {
                $workspacePermissions += $defaultWorkspaceMetadata.Permissions
            }

            if ($defaultWorkspaceConfig -and $defaultWorkspaceConfig.Permissions)
            {
                $workspacePermissions += @($defaultWorkspaceConfig.Permissions)
            }
        }

        # remove duplicate identifiers

        $workspacePermissions = $workspacePermissions |% {$_} | Group-Object identifier |% { $_.Group[0] }

        # Set new/Update permissions

        $workspacePermissions |% { 
        
            $configPermission = $_

            # FInd if the identifier is present on the workspace permissions

            $pbiPermission = $workspaceUsers |? { 
                ($_.identifier -and $_.identifier -eq $configPermission.identifier)
            }

            $body = $configPermission | select identifier, groupUserAccessRight, principalType | ConvertTo-Json
           
            if (!$pbiPermission)
            {
                Write-Host "##[debug]Adding new permission for principal '$($configPermission.identifier)' | '$($configPermission.principalType)' | '$($configPermission.groupUserAccessRight)'"
                
                Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/users" -Method Post -Body $body | Out-Null

            }
            else
            {
                if ($configPermission.groupUserAccessRight -ne $pbiPermission.groupUserAccessRight)
                {
                    Write-Host "##[debug]Updating permission for principal '$($configPermission.identifier)' | '$($configPermission.principalType)' | '$($configPermission.groupUserAccessRight)'"

                    #Invoke-PBIRequest -authToken $authToken -groupId $workspace.id -resource "users" -method Put -body $body

                    Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/users" -Method Put -Body $body | Out-Null
                }
            }          
        }

        # Clean all the permissions not existent on the config files: default & project

        if ($workspaceDeployOptions -and $workspaceDeployOptions.CleanPermissions -eq $true)
        {          
            $workspacePermissionsToDelete = @($workspaceUsers |? { 
                ($_.identifier -and $_.identifier -notin $workspacePermissions.identifier)
            })

            if ($workspacePermissionsToDelete.Count -ne 0)
            {
                Write-Host "##[debug]Cleaning permissions: $($workspacePermissionsToDelete.Count)"
            }

            foreach ($permission in $workspacePermissionsToDelete)
            {                                            
                Write-Host "##[debug]Deleting permission for principal '$($permission.identifier)'"               

                Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/users/$($permission.identifier)" -Method Delete | Out-Null
            }        
        }

        if (!$workspace.isOnDedicatedCapacity)
        {
            if ([string]::IsNullOrEmpty($capacityId))
            {
                if ($defaultWorkspaceMetadata -and ![string]::IsNullOrEmpty($defaultWorkspaceMetadata.DedicatedCapacityId))
                {
                    $capacityId = $defaultWorkspaceMetadata.DedicatedCapacityId
                }
                elseif ($defaultWorkspaceConfig -and ![string]::IsNullOrEmpty($defaultWorkspaceConfig.DedicatedCapacityId))
                {
                    $capacityId = $defaultWorkspaceConfig.DedicatedCapacityId
                }
            }

            if ([string]::IsNullOrEmpty($capacityName))
            {
                if ($defaultWorkspaceMetadata -and ![string]::IsNullOrEmpty($defaultWorkspaceMetadata.DedicatedCapacityName))
                {
                    $capacityName = $defaultWorkspaceMetadata.DedicatedCapacityName
                }
                elseif ($defaultWorkspaceConfig -and ![string]::IsNullOrEmpty($defaultWorkspaceConfig.DedicatedCapacityName))
                {
                    $capacityName = $defaultWorkspaceConfig.DedicatedCapacityName
                }
            }
      
            if ([string]::IsNullOrEmpty($capacityId) -and ![string]::IsNullOrEmpty($capacityName))
            {
                #$capacities = Invoke-PBIRequest -authToken $authToken -resource "capacities" -method Get
                $capacities = Invoke-PowerBIRestMethod -Url "capacities" -Method Get | ConvertFrom-Json | Select -ExpandProperty value

                $capacity = $capacities |? {$_.displayName -eq $capacityName} | select -First 1

                if ($capacity -and $capacity.id)
                {
                    $capacityId= $capacity.id
                }
                else
                {
                    throw "Cannot find capacity with name '$capacityName'"
                }
            }
        

            # Assign premium if asked

            if (![string]::IsNullOrEmpty($capacityId))
            {
                Write-Host "##[debug]Assigning Premium Capacity: '$capacityId'"

                #Invoke-PBIRequest -authToken $authToken -groupId $workspace.id -resource "AssignToCapacity" -method Post -body "{'capacityId':'$capacityId'}"

                Invoke-PowerBIRestMethod -Url "groups/AssignToCapacity" -Method Post -Body "{'capacityId':'$capacityId'}" | Out-Null
            
            }
        }

        Write-Host "##[endgroup]"
    }
}

# Unsuported, uses an internal API that currently is no longer supported to be called by the Microsoft PowerShell module
function Set-PBIReportConnections_Auto
{
    [CmdletBinding()]
    param(
        $path 
        ,
        $configPath
        ,
        $internalAPIURL = "https://wabi-west-europe-redirect.analysis.windows.net"
        ,
        $workingDir
        ,
        $backupDir
        ,
        $filter = @()
    )

    $rootPath = $PSScriptRoot

    if ([string]::IsNullOrEmpty($path))
    {
        $path = "$rootPath\Reports"
    }

    if ([string]::IsNullOrEmpty($backupDir))
    {
        $backupDir = "$rootPath\_Backup"
    }

    New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue | Out-Null

    if ([string]::IsNullOrEmpty($workingDir))
    {
        $workingDir = Join-Path ([System.IO.Path]::GetTempPath()) "PBIFixConnections_$((New-Guid).ToString("N"))"
    }

    New-Item -ItemType Directory -Path $workingDir -Force -ErrorAction SilentlyContinue | Out-Null

    if ([string]::IsNullOrEmpty($configPath))
    {
        $configPath = "$rootPath\config.json"
    }

    $reports = Get-ChildItem -File -Path "$path\*.pbix" -Recurse -ErrorAction SilentlyContinue

    if ($filter -and $filter.Count -gt 0)
    {
        $reports = $reports |? { $filter -contains $_.Name }
    }

    if ($reports.Count -eq 0)
    {
        Write-Host "##[warning] No reports on path '$path'"
        return
    }

    if (!(Test-Path -Path $configPath))
    {
        throw "Cannot find metadata file '$configPath'"
    }

    $environmentMetadata = Get-EnvironmentMetadata $configPath

    Write-Host "##[command]Deploying '$($reports.Count)' reports"

    $bearerToken = Get-PowerBIAccessToken -AsString
    # Get all datasets the user has access to get the modelid for the rebind

    $sharedDataSetsStr = Invoke-RestMethod -Method Get -Headers @{'Authorization' = $bearerToken} -Uri "$internalAPIURL/metadata/gallery/SharedDatasets" 

    if (!$sharedDataSetsStr)
    {
        throw "Cannot get SharedDatasets, make sure you are using the internal api for the Power BI tenant"
    }

    #ConverFrom-Json doesnt like properties with same name
    $sharedDataSetsStr = $sharedDataSetsStr.Replace("nextRefreshTime","nextRefreshTime_").Replace("lastRefreshTime","lastRefreshTime_")
    $sharedDataSets = $sharedDataSetsStr | ConvertFrom-Json

    $reports |% {

        $pbixFile = $_

        Write-Host "##[group]Fixing connection of report: '$($pbixFile.Name)'"

        $filePath = $pbixFile.FullName

        $fileName = [System.IO.Path]::GetFileName($pbixFile.FullName)

        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

        # Select the first target workspace to discover the datasetid

        $reportMetadata = Get-ReportMetadata -environmentMetadata $environmentMetadata -filePath $filePath | Select -First 1

        if (!$reportMetadata)
        {
            throw "Cannot find Report configuration '$filePath'"
        }

        $dataSetId = $reportMetadata.DataSetId

        Write-Host "##[debug]Finding dataset model id of dataset '$dataSetId'"

        # Find model for the dataset

        $model = $sharedDataSets |? { $_.model.dbName -eq $dataSetId }

        if ($model)
        {
            $modelId = $model.modelId

            Write-Host "##[debug] Found Power BI model '$modelId' for '$dataSetId'"

            Write-Host "##[debug] Backup '$fileName' into '$backupDir'"

            Copy-Item -Path $filePath -Destination  "$backupDir\$fileNameWithoutExt.$(Get-Date -Format "yyyyMMddHHmmss").pbix" -Force

            $zipFile = "$workingDir\$fileName.zip"

            $zipFolder = "$workingDir\$fileNameWithoutExt"

            Write-Host "##[command] Unziping '$fileName' into $zipFolder"

            Copy-Item -Path $filePath -Destination $zipFile -Force
        
            Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force | Out-Null

            $connectionsJson = Get-Content "$zipFolder\Connections"  | ConvertFrom-Json

            $connection = $connectionsJson.Connections[0]

            if ($connection.PbiModelDatabaseName -eq $dataSetId)
            {
                Write-Host "##[warning] PBIX '$fileName' already connects to dataset '$dataSetId' skipping the rebind"
                return
            }

            $connection.PbiServiceModelId = $modelId
            $connection.ConnectionString = $connection.ConnectionString.Replace($connection.PbiModelDatabaseName, $dataSetId)
            $connection.PbiModelDatabaseName = $dataSetId

            if($connectionsJson.RemoteArtifacts -and $connectionsJson.RemoteArtifacts.Count -ne 0)
            {
                $connectionsJson.RemoteArtifacts[0].DatasetId = $dataSetId
            }

            $connectionsJson | ConvertTo-Json -Compress | Out-File "$zipFolder\Connections" -Encoding ASCII 

            # Update the connections on zip file

            Write-Host "##[debug] Updating connections file on zip file"

            Compress-Archive -Path "$zipFolder\Connections" -CompressionLevel Optimal -DestinationPath $zipFile -Update

            # Remove SecurityBindings

            Write-Host "##[debug] Removing SecurityBindings"

            try{
                $stream = new-object IO.FileStream($zipfile, [IO.FileMode]::Open)
                $zipArchive = new-object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Update)
                $securityBindingsFile = $zipArchive.Entries |? Name -eq "SecurityBindings" | Select -First 1
            
                if ($securityBindingsFile)
                {
                    $securityBindingsFile.Delete()
                }
                else
                {
                    Write-Host "##[warning] Cannot find SecurityBindings on zip"
                }
            
            }
            finally{
                if ($zipArchive) { $zipArchive.Dispose() }
                if ($stream) { $stream.Dispose() } 
            }

            Write-Host "##[debug] Overwriting original pbix"

            Copy-Item -Path $zipfile -Destination $filePath -Force

        }
        else
        {
            Write-Host "##[warning] Cannot find a Power BI model for dataset '$dataSetId'"
        }

        Write-Host "##[endgroup]"
    }
}

function Set-PBIReportConnections
{
    [CmdletBinding()]
    param(
        $path 
        ,
        $configPath
        ,
        # Go to app.powerbi.com and network trace the call to 'https://*.analysis.windows.net/metadata/gallery/SharedDatasets" and save the file locally
        $sharedDatasetsPath
        ,
        $workingDir
        ,
        $backupDir
        ,
        $filter = @()
    )

    $rootPath = $PSScriptRoot

    if (!(Test-Path $sharedDatasetsPath))
    {
        throw "Cannot find shareddatasets file '$sharedDatasetsPath'. Login to app.powerbi.com and networktrace the 'sharedatasets' file"
    }

    if ([string]::IsNullOrEmpty($path))
    {
        $path = "$rootPath\Reports"
    }

    if ([string]::IsNullOrEmpty($backupDir))
    {
        $backupDir = "$rootPath\_Backup"
    }

    New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue | Out-Null

    if ([string]::IsNullOrEmpty($workingDir))
    {
        $workingDir = Join-Path ([System.IO.Path]::GetTempPath()) "PBIFixConnections_$((New-Guid).ToString("N"))"
    }

    New-Item -ItemType Directory -Path $workingDir -Force -ErrorAction SilentlyContinue | Out-Null

    if ([string]::IsNullOrEmpty($configPath))
    {
        $configPath = "$rootPath\config.json"
    }

    $reports = Get-ChildItem -File -Path "$path\*.pbix" -Recurse -ErrorAction SilentlyContinue

    if ($filter -and $filter.Count -gt 0)
    {
        $reports = $reports |? { $filter -contains $_.Name }
    }

    if ($reports.Count -eq 0)
    {
        Write-Host "##[warning] No reports on path '$path'"
        return
    }

    if (!(Test-Path -Path $configPath))
    {
        throw "Cannot find metadata file '$configPath'"
    }

    $environmentMetadata = Get-EnvironmentMetadata $configPath

    Write-Host "##[command]Deploying '$($reports.Count)' reports"

    $sharedDataSetsStr = Get-Content $sharedDatasetsPath

    #ConverFrom-Json doesnt like properties with same name
    $sharedDataSetsStr = $sharedDataSetsStr.Replace("nextRefreshTime","nextRefreshTime_").Replace("lastRefreshTime","lastRefreshTime_")
    $sharedDataSets = $sharedDataSetsStr | ConvertFrom-Json

    $reports |% {

        $pbixFile = $_

        Write-Host "##[group]Fixing connection of report: '$($pbixFile.Name)'"

        $filePath = $pbixFile.FullName

        $fileName = [System.IO.Path]::GetFileName($pbixFile.FullName)

        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

        # Select the first target workspace to discover the datasetid

        $reportMetadata = Get-ReportMetadata -environmentMetadata $environmentMetadata -filePath $filePath | Select -First 1

        if (!$reportMetadata)
        {
            throw "Cannot find Report configuration '$filePath'"
        }

        $dataSetId = $reportMetadata.DataSetId

        Write-Host "##[debug]Finding dataset model id of dataset '$dataSetId'"

        # Find model for the dataset

        $model = $sharedDataSets |? { $_.model.dbName -eq $dataSetId }

        if ($model)
        {
            $modelId = $model.modelId

            Write-Host "##[debug] Found Power BI model '$modelId' for '$dataSetId'"

            Write-Host "##[debug] Backup '$fileName' into '$backupDir'"

            Copy-Item -Path $filePath -Destination  "$backupDir\$fileNameWithoutExt.$(Get-Date -Format "yyyyMMddHHmmss").pbix" -Force

            $zipFile = "$workingDir\$fileName.zip"

            $zipFolder = "$workingDir\$fileNameWithoutExt"

            Write-Host "##[command] Unziping '$fileName' into $zipFolder"

            Copy-Item -Path $filePath -Destination $zipFile -Force
        
            Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force | Out-Null

            $connectionsJson = Get-Content "$zipFolder\Connections"  | ConvertFrom-Json

            $connection = $connectionsJson.Connections[0]

            if ($connection.PbiModelDatabaseName -eq $dataSetId)
            {
                Write-Host "##[warning] PBIX '$fileName' already connects to dataset '$dataSetId' skipping the rebind"
                return
            }

            $connection.PbiServiceModelId = $modelId
            $connection.ConnectionString = $connection.ConnectionString.Replace($connection.PbiModelDatabaseName, $dataSetId)
            $connection.PbiModelDatabaseName = $dataSetId

            if($connectionsJson.RemoteArtifacts -and $connectionsJson.RemoteArtifacts.Count -ne 0)
            {
                $connectionsJson.RemoteArtifacts[0].DatasetId = $dataSetId
            }

            $connectionsJson | ConvertTo-Json -Compress | Out-File "$zipFolder\Connections" -Encoding ASCII 

            # Update the connections on zip file

            Write-Host "##[debug] Updating connections file on zip file"

            Compress-Archive -Path "$zipFolder\Connections" -CompressionLevel Optimal -DestinationPath $zipFile -Update

            # Remove SecurityBindings

            Write-Host "##[debug] Removing SecurityBindings"

            try{
                $stream = new-object IO.FileStream($zipfile, [IO.FileMode]::Open)
                $zipArchive = new-object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Update)
                $securityBindingsFile = $zipArchive.Entries |? Name -eq "SecurityBindings" | Select -First 1
            
                if ($securityBindingsFile)
                {
                    $securityBindingsFile.Delete()
                }
                else
                {
                    Write-Host "##[warning] Cannot find SecurityBindings on zip"
                }
            
            }
            finally{
                if ($zipArchive) { $zipArchive.Dispose() }
                if ($stream) { $stream.Dispose() } 
            }

            Write-Host "##[debug] Overwriting original pbix"

            Copy-Item -Path $zipfile -Destination $filePath -Force

        }
        else
        {
            Write-Host "##[warning] Cannot find a Power BI model for dataset '$dataSetId'"
        }

        Write-Host "##[endgroup]"
    }
}