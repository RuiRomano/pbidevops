### Install Required PowerShell Modules (as Administrator)
```
Install-Module -Name MicrosoftPowerBIMgmt -RequiredVersion 1.2.1026
```

# How to Run?

Setup a folder with the Datasets & Reports

Change the [Config File](./config-prd.json) with your deployment scenario

Run the [Deploy](./deploy.ps1) powershell script:

```
powershell deploy.ps1 -path .\SampleProject -configPath .\config.json
```

# Sample Project

This repo includes a sample project with datasets & reports, if you try to deploy this sample project before running you need to do the following:

- Deploy the dataset to a workspace (you can use the deploy.ps1 script)
- Run the script [tool.FixReportConnections.ps1](./tool.FixReportConnections.ps1) to ensure local PBIX files target an existent powerbi.com dataset, otherwise you will get an error on report deploy

# Multiple Config Files

The main advantage of declaring your deployment environment is that you can easily have multiple deployment configurations (multiple [config](./config.json) files) and call the deploy.ps1 using the sample local development files but different deployment config.

# Multiple Config Files

Its possible to setup permissions for the workspaces, use the following json

## User
```
 {
    "identifier": "user1@company.com",
    "groupUserAccessRight": "Member",
    "principalType": "User"
}
```

## Group
```
 {
    "identifier": "[AZURE ID OBJECT ID OF THE GROUP]",
    "groupUserAccessRight": "Admin",
    "principalType": "Group"
}
```

## Service Principal / APP
```
 {
    "identifier": "[AZURE ID OBJECT ID OF THE SERVICE PRINCIPAL]",
    "groupUserAccessRight": "Member",
    "principalType": "App"
}
```