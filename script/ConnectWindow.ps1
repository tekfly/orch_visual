Add-Type -AssemblyName PresentationFramework

$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp\"
$xamlPath = Join-Path $downloadFolder "xaml_files\ConnectWindow.xaml"

if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("ConnectWindow.xaml not found.", "Error", "OK", "Error")
    exit
}

# Clean XAML and load window
$xamlRaw = Get-Content $xamlPath -Raw
$xamlClean = $xamlRaw -replace 'mc:Ignorable="[^"]*"', ''
$xamlClean = $xamlClean -replace 'xmlns:mc="[^"]*"', ''
[xml]$xaml = $xamlClean
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Hook up controls
$connectBtn = $window.FindName("ConnectBtn")
$cancelBtn  = $window.FindName("CancelBtn")
$urlBox     = $window.FindName("UrlTextBox")
$tenantBox  = $window.FindName("TenantTextBox")

$connectBtn.Add_Click({
    $url = $urlBox.Text
    $tenant = $tenantBox.Text

    [System.Windows.MessageBox]::Show("URL: $url `nTenant: $tenant")
})

$cancelBtn.Add_Click({
    $window.Close()
})

# Show the window
$window.ShowDialog() | Out-Null
