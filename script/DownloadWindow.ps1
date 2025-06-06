Add-Type -AssemblyName PresentationFramework

$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp"
$versionFile = Join-Path $downloadFolder "json_files\product_versions.json"
$jsonUrl = "https://raw.githubusercontent.com/tekfly/orch_gui/refs/heads/main/product_versions.json"
$folder_downloads = Join-Path $downloadFolder "downloads"

# Create folders if missing
foreach ($path in @($downloadFolder, (Split-Path $versionFile), $folder_downloads)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

# Download JSON if missing
if (-not (Test-Path $versionFile)) {
    try {
        Invoke-WebRequest -Uri $jsonUrl -OutFile $versionFile -UseBasicParsing
    } catch {
        [System.Windows.MessageBox]::Show("Failed to download product_versions.json.", "Error", "OK", "Error")
        exit
    }
}

# Load and parse JSON
try {
    $jsonData = Get-Content $versionFile -Raw | ConvertFrom-Json
} catch {
    [System.Windows.MessageBox]::Show("Failed to load or parse product_versions.json.", "Error", "OK", "Error")
    exit
}

$products = @("Orchestrator", "Robot/Studio", "Others")
$actionsByProduct = @{
    "Orchestrator" = @("download")
    "Robot/Studio" = @("download")
    "Others" = @("download")
}

# Load XAML UI
$xamlPath = Join-Path $downloadFolder "xaml_files\DownloadWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("DownloadWindow.xaml not found.", "Error", "OK", "Error")
    exit
}

[xml]$xaml = Get-Content $xamlPath -Raw
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI controls
$productBox     = $window.FindName("ProductBox")
$actionBox      = $window.FindName("ActionBox")
$versionBox     = $window.FindName("VersionBox")
$othersListBox  = $window.FindName("OthersListBox")
$downloadBtn    = $window.FindName("DownloadBtn")
$cancelBtn      = $window.FindName("CancelBtn")
$progressBar    = $window.FindName("ProgressBar")

# Populate product dropdown
$products | ForEach-Object { $productBox.Items.Add($_) }

# Product Selection
$productBox.Add_SelectionChanged({
    $selectedProduct = $productBox.SelectedItem
    if ($selectedProduct) {
        $actionBox.Items.Clear()
        $actionsByProduct[$selectedProduct] | ForEach-Object { $actionBox.Items.Add($_) }
        $actionBox.IsEnabled = $true

        $versionBox.Items.Clear()
        $versionBox.IsEnabled = $false
        $downloadBtn.IsEnabled = $false
        $cancelBtn.IsEnabled = $true

        $othersListBox.Items.Clear()
        $othersListBox.Visibility = if ($selectedProduct -eq "Others") { 'Visible' } else { 'Collapsed' }
    }
})

# Action Selection
$actionBox.Add_SelectionChanged({
    $selectedProduct = $productBox.SelectedItem
    $selectedAction = $actionBox.SelectedItem

    if ($selectedProduct -eq "Others") {
        $othersListBox.Items.Clear()
        $othersListBox.Tag = @{}
        $othersListBox.Visibility = 'Visible'

        $otherProducts = $jsonData.PSObject.Properties.Name | Where-Object { $_ -notin @("Orchestrator", "Robot/Studio") }

        foreach ($otherProduct in $otherProducts) {
            foreach ($ver in $jsonData.$otherProduct.PSObject.Properties.Name) {
                $display = "$otherProduct $ver"
                $othersListBox.Items.Add($display)
                $othersListBox.Tag[$display] = @{
                    Product = $otherProduct
                    Version = $ver
                    Url     = $jsonData.$otherProduct.$ver
                }
            }
        }

        $downloadBtn.IsEnabled = $true
        $versionBox.IsEnabled = $false
    }
    elseif ($selectedProduct -and $selectedAction) {
        $versionBox.Items.Clear()
        $jsonSection = $jsonData.$selectedProduct

        if ($jsonSection) {
            $jsonSection.PSObject.Properties.Name |
                Sort-Object -Descending |
                ForEach-Object { $versionBox.Items.Add($_) }
            $versionBox.IsEnabled = $true
            $downloadBtn.IsEnabled = $false
        }
    }
})

# Enable Download Button
$versionBox.Add_SelectionChanged({
    $downloadBtn.IsEnabled = !!$versionBox.SelectedItem
})

# Download Button Click
$downloadBtn.Add_Click({
    try {
        $waitingWindowXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='Downloading' SizeToContent='WidthAndHeight' WindowStartupLocation='CenterScreen' ResizeMode='NoResize'>
    <StackPanel Margin='20'>
        <TextBlock Text='Downloading, please wait...' FontSize='14' FontWeight='Bold' HorizontalAlignment='Center'/>
    </StackPanel>
</Window>
"@
        $reader = (New-Object System.Xml.XmlNodeReader ([xml]$waitingWindowXaml))
        $waitingWindow = [Windows.Markup.XamlReader]::Load($reader)
        $waitingWindow.Show()

        # Run in background job
        $job = Start-Job -ScriptBlock {
            param($product, $version, $selectedItems, $othersTag, $jsonData, $downloadFolder)

            function Download-FileInner {
                param ($url, $savePath)
                if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                    & curl.exe -L $url -o $savePath
                } else {
                    Start-BitsTransfer -Source $url -Destination $savePath
                }
            }

            if ($product -eq "Others") {
                foreach ($item in $selectedItems) {
                    $info = $othersTag[$item]
                    if ($info -and $info.Url) {
                        $filename = Split-Path $info.Url -Leaf
                        $savePath = Join-Path $downloadFolder $filename
                        Download-FileInner -url $info.Url -savePath $savePath
                    }
                }
            } else {
                $url = $jsonData.$product.$version
                $productNameForFile = ($product -split '/')[1]
                $savePath = Join-Path $downloadFolder "$productNameForFile-$version.msi"
                Download-FileInner -url $url -savePath $savePath
            }
        } -ArgumentList $productBox.SelectedItem, $versionBox.SelectedItem, @($othersListBox.SelectedItems), $othersListBox.Tag, $jsonData, $folder_downloads

        $job | Wait-Job
        $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
        $jobErrors = $job.ChildJobs[0].JobStateInfo.Reason

        $waitingWindow.Dispatcher.Invoke([action]{ $waitingWindow.Close() })

        if ($jobErrors) { throw $jobErrors }

        [System.Windows.MessageBox]::Show("Download completed.", "Success", "OK", "Information")
        Remove-Job -Job $job -Force
        $null = $jobResult
    }
    catch {
        if ($waitingWindow -and $waitingWindow.IsVisible) {
            $waitingWindow.Dispatcher.Invoke([action]{ $waitingWindow.Close() })
        }
        [System.Windows.MessageBox]::Show("Download failed: $($_.Exception.Message)", "Error", "OK", "Error")
    }
})

# Cancel button
$cancelBtn.Add_Click({ $window.Close() })

$window.ShowDialog() | Out-Null
