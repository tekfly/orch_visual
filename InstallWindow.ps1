# Define paths to XAML files
$XamlPath = Join-Path -Path $PSScriptRoot -ChildPath "xaml_files"
$InstallWindowXamlPath = Join-Path $XamlPath "InstallWindow.xaml"
$InstallTypeXamlPath = Join-Path $XamlPath "InstallTypeDialog.xaml"
$ComponentOptionsXamlPath = Join-Path $XamlPath "ComponentOptions.xaml"

# Load XAML content
[xml]$mainXaml = Get-Content -Raw -Path $InstallWindowXamlPath
[xml]$installTypeXaml = Get-Content -Raw -Path $InstallTypeXamlPath
[xml]$componentOptionsTemplate = Get-Content -Raw -Path $ComponentOptionsXamlPath

Add-Type -AssemblyName PresentationFramework

function Load-XamlWindow {
    param ([xml]$xaml)
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

$mainWindow = Load-XamlWindow $mainXaml
$installTypeWindow = Load-XamlWindow $installTypeXaml
$FilesListBox = $mainWindow.FindName("FilesListBox")
$InstallBtn = $mainWindow.FindName("InstallBtn")
$CancelBtn = $mainWindow.FindName("CancelBtn")
$ChkMsi = $mainWindow.FindName("ChkMsi")
$ChkExe = $mainWindow.FindName("ChkExe")
$ChkPs1 = $mainWindow.FindName("ChkPs1")

function Update-FileList {
    $FilesListBox.Items.Clear()
    $files = Get-ChildItem -Path $PSScriptRoot -File | Where-Object {
        ($ChkMsi.IsChecked -and $_.Extension -eq ".msi") -or
        ($ChkExe.IsChecked -and $_.Extension -eq ".exe") -or
        ($ChkPs1.IsChecked -and $_.Extension -eq ".ps1")
    }
    $files | ForEach-Object { $FilesListBox.Items.Add($_.Name) }
}

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
        [string]$FileName,
        [string[]]$Arguments
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments -join " "
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

$InstallBtn.Add_Click({
    $selectedFile = $FilesListBox.SelectedItem
    if (-not $selectedFile) {
        [System.Windows.MessageBox]::Show("Please select a file to install.")
        return
    }

    $installType = Show-InstallTypeDialog
    if (-not $installType) { return }

    $jsonPath = Join-Path $PSScriptRoot "UiPathComponents.json"
    if (-not (Test-Path $jsonPath)) {
        [System.Windows.MessageBox]::Show("Component list JSON not found.")
        return
    }

    $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
    $availableComponents = if ($installType -eq "Studio") {
        $json.studio
    } else {
        $json.robot
    }

    $selectedComponents = Show-ComponentOptionsDialog -Options $availableComponents
    if ($selectedComponents.Count -eq 0) { return }

    $filePath = Join-Path $PSScriptRoot $selectedFile
    $args = $selectedComponents | ForEach-Object { "/addlocal=$_" }
    Execute-Installer -FileName $filePath -Arguments $args
})

$CancelBtn.Add_Click({
    $mainWindow.Close()
})

Update-FileList
$mainWindow.ShowDialog() | Out-Null