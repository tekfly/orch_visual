# Define paths
$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"
$XamlPath = Join-Path $downloadFolder "xaml_files"
$jsonPath = Join-Path $downloadFolder "json_files"
$InstallWindowXamlPath = Join-Path $XamlPath "InstallWindow.xaml"
$InstallTypeXamlPath = Join-Path $XamlPath "InstallTypeDialog.xaml"
$ComponentOptionsXamlPath = Join-Path $XamlPath "ComponentOptions.xaml"
$folder_downloads = Join-Path $downloadFolder "downloads"
$masterLogPath = Join-Path $downloadFolder "install_log.txt"
$WaitingWindowXamlPath = Join-Path $XamlPath "WaitingWindow.xaml"

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

# Load windows
$mainWindow = Load-XamlWindow $mainXaml
$installTypeWindow = Load-XamlWindow $installTypeXaml
$waitingWindow = Load-XamlWindow $waitingXaml

# Find UI elements
$FilesListBox = $mainWindow.FindName("FilesListBox")
$InstallBtn = $mainWindow.FindName("InstallBtn")
$RefreshBtn = $mainWindow.FindName("RefreshBtn")
$CancelBtn = $mainWindow.FindName("CancelBtn")
$ChkMsi = $mainWindow.FindName("ChkMsi")
$ChkExe = $mainWindow.FindName("ChkExe")
$ChkPs1 = $mainWindow.FindName("ChkPs1")

# WaitingWindow controls
$progressBar = $waitingWindow.FindName("InstallProgressBar")
$statusText = $waitingWindow.FindName("InstallStatusText")

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

###############INSTALL BUTTON ###################
$InstallBtn.Add_Click({
    $selectedFiles = $FilesListBox.SelectedItems
    if (-not $selectedFiles -or $selectedFiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one file to install.")
        return
    }

    # Files requiring install type and component selection (filtered by "studio" in filename)
    $filesRequiringSelection = @()
    foreach ($selectedFile in $selectedFiles) {
        if ($selectedFile -imatch "studio") {
            $filesRequiringSelection += $selectedFile
        }
    }

    # Load JSON once outside the loop
    $jsonPath = Join-Path $jsonPath "InstallComponents.json"
    if (-not (Test-Path $jsonPath)) {
        [System.Windows.MessageBox]::Show("Component list JSON not found.")
        return
    }
    $json = Get-Content $jsonPath -Raw | ConvertFrom-Json

    # Dictionary to hold selections per file
    $installSelections = @{}

    # Ask for install type and components for each file needing it
    foreach ($file in $filesRequiringSelection) {
        $installType = Show-InstallTypeDialog
        if (-not $installType) {
            # User cancelled selection, skip this file
            continue
        }

        # Get available components dynamically from .components based on install type
        $availableComponents = $json.components.$installType

        # Show component selection dialog
        $selectedComponents = Show-ComponentOptionsDialog -Options $availableComponents

        # If no components selected, fallback to defaults for that install type
        if ($selectedComponents.Count -eq 0) {
            $selectedComponents = $json.defaults.$installType
        }

        # Save selection for later
        $installSelections[$file] = @{
            InstallType = $installType
            Components = $selectedComponents
        }
    }

    # Initialize progress bar and show waiting window
    $progressBar.Minimum = 0
    $progressBar.Maximum = $selectedFiles.Count
    $progressBar.Value = 0
    $statusText.Text = "Starting installation..."

    $waitingWindow.Show()
    Start-Sleep -Milliseconds 200

    # Installation loop
    foreach ($selectedFile in $selectedFiles) {
        $filePath = Join-Path $folder_downloads $selectedFile
        $args = @()
        $logFileName = "log_$selectedFile.txt"
        $logPath = Join-Path $downloadFolder $logFileName
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $statusText.Dispatcher.Invoke([action]{ $statusText.Text = "Installing: $selectedFile" })

        try {
            if ($installSelections.ContainsKey($selectedFile)) {
                $selection = $installSelections[$selectedFile]
                $args = @(
                    "/i", "`"$filePath`"",
                    "ADDLOCAL=" + ($selection.Components -join ","),
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
        }
        catch {
            Add-Content -Path $masterLogPath -Value "$timestamp ERROR: Failed to install '$selectedFile'. Error: $_"
            [System.Windows.MessageBox]::Show("Installation failed for $selectedFile. Check the log for details.")
        }

        $progressBar.Dispatcher.Invoke([action]{ $progressBar.Value += 1 })
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    }

    $waitingWindow.Close()
    [System.Windows.MessageBox]::Show("Installation(s) completed.")
})

$RefreshBtn.Add_Click({ Update-FileList })
$CancelBtn.Add_Click({ $mainWindow.Close() })

Update-FileList
$mainWindow.ShowDialog() | Out-Null
#update 4:12