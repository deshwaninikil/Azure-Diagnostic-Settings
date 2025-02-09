# Connect to Azure using Automation Account identity
Connect-AzAccount -Identity

# Define file paths for previous and current diagnostic settings
$PrevJsonFile = "C:\Temp\PreviousDiagSettings.json"
$CurrentJsonFile = "C:\Temp\CurrentDiagSettings.json"
$ChangeLogFile = "C:\Temp\ChangeLog.txt"  # File to track changes

# Get all Azure Subscriptions
$Subs = Get-AzSubscription
$DiagResults = @()

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

$DiagResults | ConvertTo-Json -Depth 10 | Set-Content -Path $CurrentJsonFile
Write-Host "Current diagnostic settings saved to: $CurrentJsonFile"

if (Test-Path $PrevJsonFile) {
    $PreviousDiagResults = Get-Content -Path $PrevJsonFile | ConvertFrom-Json
    $CurrentDiagResults = Get-Content -Path $CurrentJsonFile | ConvertFrom-Json

    # Compare the previous and current data
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

        # Write the changes to ChangeLog file
        $ChangeLog | Out-File -FilePath $ChangeLogFile -Force

        # Commit and push changes to GitHub
        # Set GitHub repository and branch
        $RepoPath = "C:/path/to/your/repo"  # GitHub repository path
        $BranchName = "change-diagnostic-settings"  # Name of the branch

        # Change directory to your repository
        Set-Location -Path $RepoPath

        # Create a new branch
        git checkout -b $BranchName

        # Add the changes (including the changelog and updated diagnostic settings)
        git add .

        # Commit changes
        git commit -m "Detect and log changes in diagnostic settings"

        # Push changes to GitHub
        git push origin $BranchName

        # Create a pull request using GitHub CLI
        gh pr create --base main --head $BranchName --title "Detect Diagnostic Settings Changes" --body "This PR detects and logs changes in diagnostic settings."
        
        Write-Host "Changes pushed to GitHub and PR raised."
    }
} else {
    Write-Host "No previous data found. Saving current data as baseline."
}

# Save current data as the new previous data
Copy-Item -Path $CurrentJsonFile -Destination $PrevJsonFile -Force
