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

# Map UI elements by 'Name' (no xmlns:x: prefix needed)
$controls = @{}
$xaml.SelectNodes('//*') | Where-Object { $_.Attributes["Name"] } | ForEach-Object {
    $name = $_.Attributes["Name"].Value
    $controls[$name] = $window.FindName($name)
}

$extensionsPanel = $controls["ExtensionsPanel"]
$checkboxes = @{}

function Refresh-Checkboxes {
    $extensionsPanel.Children.Clear()
    $checkboxes.Clear()

    $action = $controls["ActionBox"].SelectedItem.Content.ToLower()

    foreach ($comp in $json.components) {
        $cmd = $json.commands.$comp.$action
        if ($cmd) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $comp
            $cb.Name = $comp

            # Try check logic if defined
            $checkCmd = $json.commands.$comp.check
            if ($checkCmd) {
                try {
                    $isInstalled = Invoke-Expression $checkCmd
                    if ($isInstalled) {
                        $cb.IsChecked = $true
                    }
                } catch {
                    # Skip errors silently
                }
            }

            $extensionsPanel.Children.Add($cb)
            $checkboxes[$comp] = $cb
        }
    }
}

# Initial load
Refresh-Checkboxes

# Action dropdown change listener
$controls["ActionBox"].Add_SelectionChanged({ Refresh-Checkboxes })

# Execute button logic
$controls["ExecuteBtn"].Add_Click({
    $controls["ProgressBar"].IsIndeterminate = $true
    $action = $controls["ActionBox"].SelectedItem.Content.ToLower()

    foreach ($comp in $json.components) {
        $cb = $checkboxes[$comp]
        if ($cb -and $cb.IsChecked -eq $true) {
            $cmd = $json.commands.$comp.$action
            if ($cmd) {
                Write-Host "Running: $comp ($action)"
                try {
                    Invoke-Expression $cmd
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to execute command for $comp")
                }
            } else {
                [System.Windows.MessageBox]::Show("No '$action' command defined for $comp")
            }
        }
    }

    $controls["ProgressBar"].IsIndeterminate = $false
    [System.Windows.MessageBox]::Show("Operation complete.")
    Refresh-Checkboxes
})

# Cancel button logic
$controls["CancelBtn"].Add_Click({ $window.Close() })

# Show the window
$window.ShowDialog() | Out-Null
