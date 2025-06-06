Add-Type -AssemblyName PresentationFramework

$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp\"
$xamlPath = Join-Path $downloadFolder "xaml_files\ConnectWindow.xaml"

if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("ConnectWindow.xaml not found.", "Error", "OK", "Error")
    exit
}

# Clean up XAML
$xamlRaw = Get-Content $xamlPath -Raw
$xamlClean = $xamlRaw -replace 'mc:Ignorable="[^"]*"', ''
$xamlClean = $xamlClean -replace 'xmlns:mc="[^"]*"', ''
[xml]$xaml = $xamlClean

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Hook up controls
$orchUrlBox    = $window.FindName("OrchUrl_textbox")
$clientIdBox   = $window.FindName("ClientID_textbox")
$secretBox     = $window.FindName("secret_textbox")
$connectBtn    = $window.FindName("ConnectBtn")
$cancelBtn     = $window.FindName("CancelBtn")

# Define a shared scope for the results
$script:OrchestratorConnection = @{}

# Event: Connect
$connectBtn.Add_Click({
    $url = $orchUrlBox.Text.Trim()
    $clientId = $clientIdBox.Text.Trim()
    $secret = $secretBox.Text.Trim()

    if (-not $url -or -not $clientId -or -not $secret) {
        [System.Windows.MessageBox]::Show("Please fill in all fields before connecting.", "Missing Information", "OK", "Warning")
        return
    }

    # Store values in a global dictionary
    $script:OrchestratorConnection = @{
        Url       = $url
        ClientId  = $clientId
        Secret    = $secret
    }

    $window.Close()
})

# Event: Cancel
$cancelBtn.Add_Click({
    $script:OrchestratorConnection = $null
    $window.Close()
})

# Show window
$window.ShowDialog() | Out-Null

# Use the values after the dialog closes
if ($script:OrchestratorConnection) {
    Write-Host "URL: $($script:OrchestratorConnection.Url)"
    Write-Host "Client ID: $($script:OrchestratorConnection.ClientId)"
    Write-Host "Secret: $($script:OrchestratorConnection.Secret)"
} else {
    Write-Host "Connection cancelled or data missing."
}
