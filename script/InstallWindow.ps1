# Define paths
$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"
$XamlPath = Join-Path $downloadFolder "xaml_files"
$InstallWindowXamlPath = Join-Path $XamlPath "InstallWindow.xaml"
$InstallTypeXamlPath = Join-Path $XamlPath "InstallTypeDialog.xaml"
$ComponentOptionsXamlPath = Join-Path $XamlPath "ComponentOptions.xaml"
$WaitingWindowXamlPath = Join-Path $XamlPath "WaitingWindow.xaml"
$folder_downloads = Join-Path $downloadFolder "downloads"
$masterLogPath = Join-Path $downloadFolder "install_log.txt"

# Define shared install parameters
$quietSwitch = "/qn"
$logSwitch = "/l*vx"
$chromeInstallParams = @(
    "--silent",
    "--do-not-launch-chrome",
    "--no-default-browser-check"
)

# Load XAML files
[xml]$mainXaml = Get-Content -Raw -Path $InstallWindowXamlPath
[xml]$installTypeXaml = Get-Content -Raw -Path $InstallTypeXamlPath
[xml]$componentOptionsTemplate = Get-Content -Raw -Path $ComponentOptionsXamlPath
[xml]$waitingXaml = Get-Content -Raw -Path $WaitingWindowXamlPath

Add-Type -AssemblyName PresentationFramework

function Load-XamlWindow {
    param ([xml]$xaml)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    return [Windows.Markup.XamlReader]::Load($reader)
}

# GUI elements
$mainWindow = Load-XamlWindow $mainXaml
$installTypeWindow = Load-XamlWindow $installTypeXaml
$waitingWindow = Load-XamlWindow $waitingXaml

$FilesListBox = $mainWindow.FindName("FilesListBox")
$InstallBtn = $mainWindow.FindName("InstallBtn")
$RefreshBtn = $mainWindow.FindName("RefreshBtn")
$CancelBtn = $mainWindow.FindName("CancelBtn")
$ChkMsi = $mainWindow.FindName("ChkMsi")
$ChkExe = $mainWindow.FindName("ChkExe")
$ChkPs1 = $mainWindow.FindName("ChkPs1")

function Update-FileList {
    $FilesListBox.Items.Clear()
    $files = Get-ChildItem -Path $folder_downloads -File | Where-Object {
        ($ChkMsi.IsChecked -and $_.Extension -eq ".msi") -or
        ($ChkExe.IsChecked -and $_.Extension -eq ".exe") -or
        ($ChkPs1.IsChecked -and $_.Extension -eq ".ps1")
    }
    $files | ForEach-Object { $FilesListBox.Items.Add($_.Name) }
}

# Checkbox events
$ChkMsi.Add_Checked({ Update-FileList })
$ChkExe.Add_Checked({ Update-FileList })
$ChkPs1.Add_Checked({ Update-FileList })
$ChkMsi.Add_Unchecked({ Update-FileList })
$ChkExe.Add_Unchecked({ Update-FileList })
$ChkPs1.Add_Unchecked({ Update-FileList })

function Show-InstallTypeDialog {
    $choice = $null
    $installTypeWindow.FindName("StudioBtn").Add_Click({ $choice = "Studio"; $installTypeWindow.Close() })
    $installTypeWindow.FindName("RobotBtn").Add_Click({ $choice = "Robot"; $installTypeWindow.Close() })
    $installTypeWindow.ShowDialog() | Out-Null
    return $choice
}

function Show-ComponentOptionsDialog {
    param ([string[]]$Options)
    [xml]$xaml = Get-Content -Raw -Path $ComponentOptionsXamlPath
    $window = Load-XamlWindow $xaml
    $panel = $window.FindName("ComponentsPanel")
    $checkboxes = @{}

    foreach ($option in $Options) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $option
        $cb.Margin = '5'
        $panel.Children.Add($cb)
        $checkboxes[$option] = $cb
    }

    $selected = @()
    $window.FindName("OkBtn").Add_Click({
        $checkboxes.GetEnumerator() | ForEach-Object {
            if ($_.Value.IsChecked) { $selected += $_.Key }
        }
        $window.Close()
    })
    $window.FindName("CancelBtn").Add_Click({
        $selected = @()
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
    return $selected
}

function Execute-Installer {
    param (
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$LogFile
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
}

$InstallBtn.Add_Click({
    $selectedFiles = $FilesListBox.SelectedItems
    if (-not $selectedFiles -or $selectedFiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one file to install.")
        return
    }

    $waitingWindow.Show()
    Start-Sleep -Milliseconds 200

    foreach ($selectedFile in $selectedFiles) {
        $filePath = Join-Path $folder_downloads $selectedFile
        $args = @()
        $logFileName = "log_$selectedFile.txt"
        $logPath = Join-Path $downloadFolder $logFileName
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        try {
            if ($selectedFile -match "Studio|Robot") {
                $installType = Show-InstallTypeDialog
                if (-not $installType) { continue }

                $jsonPath = Join-Path $PSScriptRoot "UiPathComponents.json"
                if (-not (Test-Path $jsonPath)) {
                    [System.Windows.MessageBox]::Show("Component list JSON not found.")
                    continue
                }

                $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
                $availableComponents = if ($installType -eq "Studio") { $json.studio } else { $json.robot }
                $selectedComponents = Show-ComponentOptionsDialog -Options $availableComponents
                if ($selectedComponents.Count -eq 0) { continue }

                $args = @(
                    "/i", "`"$filePath`"",
                    ($selectedComponents | ForEach-Object { "ADDLOCAL=$_" }) -join ",",
                    "$logSwitch `"$logPath`"",
                    $quietSwitch
                )
                Execute-Installer -FilePath "msiexec.exe" -Arguments $args -LogFile $logPath
            }
            elseif ($selectedFile -match "chrome" -and $selectedFile -like "*.exe") {
                Execute-Installer -FilePath $filePath -Arguments $chromeInstallParams -LogFile $logPath
            }
            elseif ($selectedFile -like "*.msi") {
                $args = @("/i", "`"$filePath`"", "$logSwitch `"$logPath`"", $quietSwitch)
                Execute-Installer -FilePath "msiexec.exe" -Arguments $args -LogFile $logPath
            }
            elseif ($selectedFile -like "*.exe") {
                $args = @("/S", "/quiet", "/norestart")
                Execute-Installer -FilePath $filePath -Arguments $args -LogFile $logPath
            }

            Add-Content -Path $masterLogPath -Value "$timestamp SUCCESS: Installed '$selectedFile' with args: $($args -join ' ')"
        } catch {
            Add-Content -Path $masterLogPath -Value "$timestamp ERROR: Failed to install '$selectedFile'. Error: $_"
            [System.Windows.MessageBox]::Show("Installation failed for $selectedFile. Check the log for details.")
        }
    }

    $waitingWindow.Close()
    [System.Windows.MessageBox]::Show("Installation(s) completed.")
})

$RefreshBtn.Add_Click({ Update-FileList })
$CancelBtn.Add_Click({ $mainWindow.Close() })

Update-FileList
$mainWindow.ShowDialog() | Out-Null
