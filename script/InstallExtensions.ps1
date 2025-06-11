Add-Type -AssemblyName PresentationFramework

# Define paths
$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"
$XamlPath = Join-Path $downloadFolder "xaml_files\InstallExtensions.xaml"
$jsonPath = Join-Path $downloadFolder "json_files\extensions.json"

# Load JSON config
if (!(Test-Path $jsonPath)) {
    Write-Error "Extensions Config file not found: $jsonPath"
    exit
}
$json = Get-Content $jsonPath -Raw | ConvertFrom-Json

# Load the WPF UI
if (!(Test-Path $XamlPath)) {
    Write-Error "XAML file not found: $XamlPath"
    exit
}
[xml]$xaml = Get-Content -Path $XamlPath
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Map UI elements
$controls = @{}
$xaml.SelectNodes("//*[@x:Name]") | ForEach-Object {
    $controls[$_.GetAttribute("x:Name")] = $window.FindName($_.GetAttribute("x:Name"))
}

# Get the dynamic checkbox panel
$extensionsPanel = $controls["ExtensionsPanel"]
$checkboxes = @{}

# Dynamically create checkboxes from the JSON component list
foreach ($comp in $json.components) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $comp
    $cb.Name = $comp
    $extensionsPanel.Children.Add($cb)
    $checkboxes[$comp] = $cb
}

# Execute button logic
$controls["ExecuteBtn"].Add_Click({
    $controls["ProgressBar"].IsIndeterminate = $true
    $action = $controls["ActionBox"].SelectedItem.Content.ToLower()

    foreach ($comp in $json.components) {
        $cb = $checkboxes[$comp]
        if ($cb.IsChecked -eq $true) {
            $cmd = $json.commands.$comp.$action
            if ($cmd) {
                Write-Host "Running: $comp ($action)"
                Invoke-Expression $cmd
            } else {
                [System.Windows.MessageBox]::Show("No '$action' command defined for $comp")
            }
        }
    }

    $controls["ProgressBar"].IsIndeterminate = $false
    [System.Windows.MessageBox]::Show("Operation complete.")
})

# Cancel button logic
$controls["CancelBtn"].Add_Click({ $window.Close() })

# Show the window
$window.ShowDialog() | Out-Null
