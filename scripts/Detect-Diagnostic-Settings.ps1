# Define file paths for previous and current diagnostic settings
$PrevJsonFile = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\PreviousDiagSettings.json"
$CurrentJsonFile = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\CurrentDiagSettings.json"
$ChangeLogFile = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\ChangeLog.txt"  # File to track changes
 
# Get all Azure Subscriptions
$Subs = Get-AzSubscription
if (-not $Subs) {
    Write-Host "No subscriptions found. Exiting script."
    exit 1
}
 
$DiagResults = @()
 
foreach ($Sub in $Subs) {
    Set-AzContext -SubscriptionId $Sub.Id | Out-Null
    Write-Host "Processing Subscription: $($Sub.Name)"
 
    $Resources = Get-AzResource
    if (-not $Resources) {
        Write-Host "No resources found in subscription: $($Sub.Name)"
        continue
    }
 
    foreach ($res in $Resources) {
        $DiagSettings = Get-AzDiagnosticSetting -ResourceId $res.ResourceId -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $DiagSettings) {
            Write-Host "No diagnostic settings found for resource: $($res.Name)"
            continue
        }
 
        foreach ($diag in $DiagSettings) {
            Write-Host "diag settings: $($diag)"
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
 
$DiagResults | ConvertTo-Json -Depth 10 | Set-Content -Path $CurrentJsonFile
Write-Host "Current diagnostic settings saved to: $CurrentJsonFile"
 
# Check if the previous file exists and has valid content
if (Test-Path $PrevJsonFile) {
    $PreviousDiagResults = Get-Content -Path $PrevJsonFile | ConvertFrom-Json
    if (-not $PreviousDiagResults) {
        Write-Host "Previous JSON file exists but is empty. Initializing an empty array."
        $PreviousDiagResults = @()
    }
} else {
    Write-Host "No previous data found. Saving current data as baseline."
    Copy-Item -Path $CurrentJsonFile -Destination $PrevJsonFile -Force
    exit 0
}
 
$CurrentDiagResults = Get-Content -Path $CurrentJsonFile | ConvertFrom-Json
if (-not $CurrentDiagResults) {
    Write-Host "Error: Current JSON file is empty. Exiting."
    exit 1
}
 
# Compare previous and current data
$Changes = Compare-Object -ReferenceObject $PreviousDiagResults -DifferenceObject $CurrentDiagResults -Property ResourceName, DiagnosticSettingsName, StorageAccount, EventHub, Workspace, Metrics, Logs, Subscription, ResourceId -PassThru
 
# Process and log changes
$ChangeDetected = $false
$ChangeLog = ""
 
foreach ($change in $Changes) {
    $Action = switch ($change.SideIndicator) {
        "=>" { "Added" }
        "<=" { "Removed" }
        "==" { "Unchanged" }
    }
    $ChangeLog += "$($change.ResourceName) - $($change.DiagnosticSettingsName): $Action`n"
    $ChangeDetected = $true
}
 
if ($ChangeDetected) {
    Write-Host "Changes detected. Logging the changes."
    $ChangeLog | Out-File -FilePath $ChangeLogFile -Force
} else {
    Write-Host "No changes detected."
}
 
# Save current data as the new previous data
Copy-Item -Path $CurrentJsonFile -Destination $PrevJsonFile -Force