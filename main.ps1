# Relaunch script as Administrator if not already elevated
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {

    $cmd = 'irm https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/main.ps1 | iex'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `$ErrorActionPreference = 'Stop'; $cmd"
    Start-Process powershell -ArgumentList $arguments -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework

# Global download folder
$global:downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"
$global:scriptFolder = Join-Path $global:downloadFolder "script"

# URLs
$productVersionsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/product_versions.json"
$installComponentsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/InstallComponents.json"
$extensionsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/extensions.json"
$downloadWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/script/DownloadWindow.ps1"
$installWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/script/InstallWindow.ps1"
$connectWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/script/ConnectWindow.ps1"
$installExtensionsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/script/InstallExtensions.ps1"

# XAML URLs
$xamlFiles = @(
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/MainWindow.xaml";        FileName = "MainWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallWindow.xaml";     FileName = "InstallWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/DownloadWindow.xaml";    FileName = "DownloadWindow.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/ComponentOptions.xaml";  FileName = "ComponentOptions.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallTypeDialog.xaml"; FileName = "InstallTypeDialog.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallExtensions.xaml"; FileName = "InstallExtensions.xaml" },
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/Connect.xaml"; FileName ="ConnectWindow.xaml"}
    @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/WaitingWindow.xaml"; FileName ="WaitingWindow.xaml"}
)

function Download-Files {
    # Create folders
    $jsonFolder = Join-Path $global:downloadFolder "json_files"
    $xamlFolder = Join-Path $global:downloadFolder "xaml_files"
    $scriptFolder = Join-Path $global:downloadFolder "script"
    $downloadFolder = Join-Path $global:downloadFolder "downloads"

    foreach ($folder in @($global:downloadFolder, $jsonFolder, $xamlFolder, $scriptFolder, $downloadFolder)) {
        if (-not (Test-Path $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
    }

    # Download static files
    $files = @(
        @{ Url = $productVersionsUrl; FileName = "product_versions.json"; Folder = $jsonFolder },
        @{ Url = $installComponentsUrl; FileName = "InstallComponents.json"; Folder = $jsonFolder },
        @{ Url = $extensionsUrl; FileName = "extensions.json"; Folder = $jsonFolder },
        @{ Url = $downloadWindowUrl; FileName = "DownloadWindow.ps1"; Folder = $global:scriptFolder },
        @{ Url = $installWindowUrl; FileName = "InstallWindow.ps1"; Folder = $global:scriptFolder },
        @{ Url = $connectWindowUrl; FileName = "ConnectWindow.ps1"; Folder = $global:scriptFolder },
        @{ Url = $installExtensionsUrl; FileName = "InstallExtensions.ps1"; Folder = $global:scriptFolder }
    )

    foreach ($file in $files) {
        $dest = Join-Path $file.Folder $file.FileName
        try {
            Invoke-WebRequest -Uri $file.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($file.FileName):`n$($_.Exception.Message)", "Download Error", "OK", "Error")
            exit
        }
    }

    # Download XAMLs
    foreach ($xaml in $xamlFiles) {
        $dest = Join-Path $xamlFolder $xaml.FileName
        try {
            Invoke-WebRequest -Uri $xaml.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($xaml.FileName):`n$($_.Exception.Message)", "Download Error", "OK", "Error")
            exit
        }
    }
}

# ---------- DOWNLOAD EVERYTHING FIRST ----------
Download-Files

# ---------- LOAD AND CLEAN XAML ----------
$xamlPath = Join-Path $global:downloadFolder "xaml_files\MainWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("MainWindow.xaml not found after download.", "Error", "OK", "Error")
    exit
}

# Remove unsupported markup
$xamlRaw = Get-Content $xamlPath -Raw
$xamlClean = $xamlRaw -replace 'mc:Ignorable="[^"]*"', ''
$xamlClean = $xamlClean -replace 'xmlns:mc="[^"]*"', ''
[xml]$xaml = $xamlClean
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# ---------- UI ELEMENTS ----------
$statusText   = $window.FindName("StatusText")
$progressBar  = $window.FindName("ProgressBar")
$btnFiles     = $window.FindName("BtnFiles")
$btnDownload  = $window.FindName("BtnDownload")
$btnInstall   = $window.FindName("BtnInstall")
$btnConnect   = $window.FindName("BtnConnect")
$btnUpdate    = $window.FindName("BtnUpdate")
$btnExtentions    = $window.FindName("BtnExtentions")


# Initialize UI
$statusText.Text = "Ready."
$progressBar.Value = 100
$btnDownload.IsEnabled = $true
$btnInstall.IsEnabled = $true
$btnConnect.IsEnabled = $true
$btnUpdate.IsEnabled = $true
$btnExtentions.IsEnabled = $true

# ---------- BUTTON EVENTS ----------
$btnFiles.Add_Click({
    $statusText.Text = "Updating files..."
    $progressBar.Value = 0
    Download-Files
    $progressBar.Value = 100
    $statusText.Text = "Update complete."
})

$btnDownload.Add_Click({
    $script = Join-Path $global:scriptFolder "DownloadWindow.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("DownloadWindow.ps1 not found.", "Error", "OK", "Error")
    }
})

$btnInstall.Add_Click({
    $script = Join-Path $global:scriptFolder "InstallWindow.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("InstallWindow.ps1 not found.", "Error", "OK", "Error")
    }
})

$btnConnect.Add_Click({
    $script = Join-Path $global:scriptFolder "ConnectWindow.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("ConnectWindow.ps1 not found.", "Error", "OK", "Error")
    }
    #[System.Windows.MessageBox]::Show("Connect clicked.") 
})


$btnUpdate.Add_Click({ [System.Windows.MessageBox]::Show("Update clicked.") })

$btnExtentions.Add_Click({
        $script = Join-Path $global:scriptFolder "InstallExtensions.ps1"
    if (Test-Path $script) {
        & $script
    } else {
        [System.Windows.MessageBox]::Show("InstallExtensions.ps1 not found.", "Error", "OK", "Error")
    }
    #[System.Windows.MessageBox]::Show("Extensions clicked.") 
})

# ---------- SHOW UI ----------
$window.ShowDialog() | Out-Null
