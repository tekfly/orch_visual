Add-Type -AssemblyName PresentationFramework

# Global download folder
$global:downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"

# URLs
$productVersionsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/product_versions.json"
$installComponentsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/InstallComponents.json"
$downloadWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/DownloadWindow.ps1"
$installWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/InstallWindow.ps1"

# XAML URLs
$xamlFiles = @(
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/MainWindow.xaml";        FileName = "MainWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallWindow.xaml";     FileName = "InstallWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/DownloadWindow.xaml";    FileName = "DownloadWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/ComponentOptions.xaml";  FileName = "ComponentOptions.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallTypeDialog.xaml"; FileName = "InstallTypeDialog.xaml" }
)

function Download-Files {
    # Create all required folders
    $jsonFolder = Join-Path $global:downloadFolder "json_files"
    $xamlFolder = Join-Path $global:downloadFolder "xaml_files"

    foreach ($folder in @($global:downloadFolder, $jsonFolder, $xamlFolder)) {
        if (-not (Test-Path $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
    }

    # Files to download
    $files = @(
        @{ Url = $productVersionsUrl; FileName = "product_versions.json"; Folder = $jsonFolder },
        @{ Url = $installComponentsUrl; FileName = "InstallComponents.json"; Folder = $jsonFolder },
        @{ Url = $downloadWindowUrl; FileName = "DownloadWindow.ps1"; Folder = $global:downloadFolder },
        @{ Url = $installWindowUrl; FileName = "InstallWindow.ps1"; Folder = $global:downloadFolder }
    )

    foreach ($file in $files) {
        $dest = Join-Path $file.Folder $file.FileName
        $statusText.Text = "Downloading $($file.FileName)..."
        try {
            Invoke-WebRequest -Uri $file.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($file.FileName):`n$($_.Exception.Message)", "Download Error", "OK", "Error")
            exit
        }
    }

    foreach ($xaml in $xamlFiles) {
        $dest = Join-Path $xamlFolder $xaml.FileName
        $statusText.Text = "Downloading $($xaml.FileName)..."
        try {
            Invoke-WebRequest -Uri $xaml.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($xaml.FileName):`n$($_.Exception.Message)", "Download Error", "OK", "Error")
            exit
        }
    }

    $progressBar.Value = 100
    $statusText.Text = "Downloads complete."
}

# -------------------

# Load MainWindow.xaml from downloaded folder
$xamlPath = Join-Path $global:downloadFolder "xaml_files\MainWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("MainWindow.xaml not found after download.", "Error", "OK", "Error")
    exit
}

[xml]$xaml = Get-Content $xamlPath -Raw
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Find controls
$statusText   = $window.FindName("StatusText")
$progressBar  = $window.FindName("ProgressBar")
$btnFiles     = $window.FindName("BtnFiles")
$btnDownload  = $window.FindName("BtnDownload")
$btnInstall   = $window.FindName("BtnInstall")
$btnConnect   = $window.FindName("BtnConnect")
$btnUpdate    = $window.FindName("BtnUpdate")

# Disable buttons initially
$btnDownload.IsEnabled = $false
$btnInstall.IsEnabled = $false
$btnConnect.IsEnabled = $false
$btnUpdate.IsEnabled = $false

# Call Download-Files now that UI controls are available
Download-Files

# Enable buttons after download completes
$btnDownload.IsEnabled = $true
$btnInstall.IsEnabled = $true
$btnConnect.IsEnabled = $true
$btnUpdate.IsEnabled = $true

# Button Click Handlers
$btnFiles.Add_Click({
    $statusText.Text = "Updating files..."
    $progressBar.Value = 0
    Download-Files
    $btnDownload.IsEnabled = $true
    $btnInstall.IsEnabled = $true
    $btnConnect.IsEnabled = $true
    $btnUpdate.IsEnabled = $true
    $statusText.Text = "Update complete."
})

$btnDownload.Add_Click({
    $script = Join-Path $global:downloadFolder "DownloadWindow.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("DownloadWindow.ps1 not found.", "Error", "OK", "Error")
    }
})

$btnInstall.Add_Click({
    $script = Join-Path $global:downloadFolder "InstallWindow.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("InstallWindow.ps1 not found.", "Error", "OK", "Error")
    }
})

$btnConnect.Add_Click({ [System.Windows.MessageBox]::Show("Connect clicked.") })
$btnUpdate.Add_Click({ [System.Windows.MessageBox]::Show("Update clicked.") })

# Show window
$window.ShowDialog() | Out-Null
