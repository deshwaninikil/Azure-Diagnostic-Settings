# Define file paths
$BasePath = "C:\Users\lenovo\Desktop\Diagnostic"
$PrevJsonFile = "$BasePath\PreviousDiagSettings.json"
$CurrentJsonFile = "$BasePath\CurrentDiagSettings.json"
$ChangeLogFile = "$BasePath\ChangeLog.txt"

# Ensure directory exists
if (!(Test-Path $BasePath)) {
    New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
}

# Connect to Azure
try {
    $AzureLogin = Get-AzSubscription -ErrorAction Stop
    Write-Host "Azure login verified."
} catch {
    Write-Host "Not logged into Azure. Attempting login..."
    Connect-AzAccount | Out-Null
}

# Retrieve all Azure subscriptions
$Subs = Get-AzSubscription
$DiagResults = @()

# Loop through subscriptions and fetch diagnostic settings
foreach ($Sub in $Subs) {
    Set-AzContext -SubscriptionId $Sub.Id | Out-Null
    Write-Host "Processing Subscription: $($Sub.Name)"

    $Resources = Get-AzResource
    foreach ($res in $Resources) {
        $DiagSettings = Get-AzDiagnosticSetting -ResourceId $res.ResourceId -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        foreach ($diag in $DiagSettings) {
            $item = [PSCustomObject]@{
                ResourceName = $res.Name
                DiagnosticSettingsName = $diag.Name
                StorageAccount = $diag.StorageAccountId -split '/' | Select-Object -Last 1
                EventHub = $diag.EventHubAuthorizationRuleId -split '/' | Select-Object -Last 3 | Select-Object -First 1
                Workspace = $diag.WorkspaceId -split '/' | Select-Object -Last 1
                Metrics = ($diag.Metrics | ConvertTo-Json -Compress).Trim()
                Logs = ($diag.Logs | ConvertTo-Json -Compress).Trim()
                Subscription = $Sub.Name
                ResourceId = $res.ResourceId
            }
            $DiagResults += $item
        }
    }
}

# Save current diagnostic settings
$DiagResults | ConvertTo-Json -Depth 10 | Set-Content -Path $CurrentJsonFile -Force
Write-Host "Current diagnostic settings saved to: $CurrentJsonFile"

# Check for previous JSON file
if (!(Test-Path $PrevJsonFile)) {
    Write-Host "No previous data found. Saving current data as baseline."
    Copy-Item -Path $CurrentJsonFile -Destination $PrevJsonFile -Force
    exit
}

# Load previous and current data safely
$PreviousDiagResults = if ((Get-Content -Path $PrevJsonFile -Raw) -ne "") { Get-Content -Path $PrevJsonFile -Raw | ConvertFrom-Json } else { @() }
$CurrentDiagResults = if ((Get-Content -Path $CurrentJsonFile -Raw) -ne "") { Get-Content -Path $CurrentJsonFile -Raw | ConvertFrom-Json } else { @() }

Write-Host "PreviousDiagResults Count: $($PreviousDiagResults.Count)"
Write-Host "CurrentDiagResults Count: $($CurrentDiagResults.Count)"

# Compare previous and current settings
if ($PreviousDiagResults.Count -eq 0 -or $CurrentDiagResults.Count -eq 0) {
    Write-Host "Skipping comparison: One or both JSON files are empty."
} else {
    $Changes = Compare-Object -ReferenceObject $PreviousDiagResults -DifferenceObject $CurrentDiagResults `
        -Property ResourceName, DiagnosticSettingsName, StorageAccount, EventHub, Workspace, Metrics, Logs, Subscription, ResourceId -PassThru

    $ChangeLog = ""
    foreach ($change in $Changes) {
        $Action = switch ($change.SideIndicator) {
            "=>" { "Added" }
            "<=" { "Removed" }
            "==" { "Unchanged" }
        }
        $ChangeLog += "$($change.ResourceName) - $($change.DiagnosticSettingsName): $Action`n"
    }

    if ($ChangeLog) {
        Write-Host "Changes detected. Logging changes."
        $ChangeLog | Out-File -FilePath $ChangeLogFile -Force
    }
}

# Update previous settings file
Copy-Item -Path $CurrentJsonFile -Destination $PrevJsonFile -Force
