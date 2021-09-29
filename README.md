# pbidevops


config.json
deployOptions
- permissions removal

shareddatasets.json

Publish reports commands
filter command in PS 
```powershell
# Deploy Reports

Publish-PBIReports -configPath $configPath -path "$projectPath\Reports" -filter @("Customer.pbix","Purchases.pbix")
```