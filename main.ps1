Add-Type -AssemblyName PresentationFramework

# Download folder
$global:downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"

# Define URLs
$productVersionsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/product_versions.json"
$installComponentsUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/json_files/InstallComponents.json"
$downloadWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/DownloadWindow.ps1"
$installWindowUrl = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/InstallWindow.ps1"

# Ensure main folder exists
if (-not (Test-Path $downloadFolder)) {
    New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
}

function Download-Files {
    $files = @(
        @{ Url = $productVersionsUrl; FileName = "product_versions.json" },
        @{ Url = $installComponentsUrl; FileName = "InstallComponents.json" },
        @{ Url = $downloadWindowUrl; FileName = "DownloadWindow.ps1" },
        @{ Url = $installWindowUrl; FileName = "InstallWindow.ps1" }
    )

    # Create folders
    $jsonFolder = Join-Path $downloadFolder "json_files"
    $xamlFolder = Join-Path $downloadFolder "xaml_files"
    foreach ($folder in @($jsonFolder, $xamlFolder)) {
        if (-not (Test-Path $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
    }

    # Download JSON and PS1 files
    for ($i = 0; $i -lt $files.Count; $i++) {
        $file = $files[$i]
        $ext = [System.IO.Path]::GetExtension($file.FileName)
        $savePath = if ($ext -eq ".json") {
            Join-Path $jsonFolder $file.FileName
        } else {
            Join-Path $downloadFolder $file.FileName
        }

        $statusText.Text = "Downloading $($file.FileName)..."
        $progressBar.Value = [math]::Round(($i / $files.Count) * 100)

        try {
            Invoke-WebRequest -Uri $file.Url -OutFile $savePath -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($file.FileName):`n$($_.Exception.Message)", "Error", "OK", "Error")
            return
        }
    }

    # Download XAML files
    $xamlFiles = @(
        @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallWindow.xaml";     FileName = "InstallWindow.xaml" },
        @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/DownloadWindow.xaml";    FileName = "DownloadWindow.xaml" },
        @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/MainWindow.xaml";        FileName = "MainWindow.xaml" },
        @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/ComponentOptions.xaml";  FileName = "ComponentOptions.xaml" },
        @{ Url = "https://raw.githubusercontent.com/tekfly/orch_visual/refs/heads/main/xaml_files/InstallTypeDialog.xaml"; FileName = "InstallTypeDialog.xaml" }
    )

    foreach ($file in $xamlFiles) {
        $savePath = Join-Path $xamlFolder $file.FileName
        $statusText.Text = "Downloading $($file.FileName)..."
        try {
            Invoke-WebRequest -Uri $file.Url -OutFile $savePath -UseBasicParsing -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to download $($file.FileName):`n$($_.Exception.Message)", "Error", "OK", "Error")
            return
        }
    }

    $progressBar.Value = 100
    $statusText.Text = "Downloads complete."
    $btnDownload.IsEnabled = $true
    $btnInstall.IsEnabled = $true
    $btnConnect.IsEnabled = $true
    $btnUpdate.IsEnabled = $true
    [System.Windows.MessageBox]::Show("Files downloaded to:`n$downloadFolder", "Done", "OK", "Information")
}

# Load the downloaded MainWindow.xaml
$xamlPath = Join-Path $downloadFolder "xaml_files\MainWindow.xaml"
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

# Button handlers
$btnFiles.Add_Click({
    $statusText.Text = "Updating files..."
    $progressBar.Value = 0
    Download-Files
})

$btnDownload.Add_Click({
    & "$global:downloadFolder\DownloadWindow.ps1"
})

$btnInstall.Add_Click({
    & "$global:downloadFolder\InstallWindow.ps1"
})

$btnConnect.Add_Click({
    [System.Windows.MessageBox]::Show("Connect clicked.")
})

$btnUpdate.Add_Click({
    [System.Windows.MessageBox]::Show("Update clicked.")
})

# Show UI
$window.ShowDialog() | Out-Null
#update2