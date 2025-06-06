Add-Type -AssemblyName PresentationFramework

$downloadFolder = Join-Path $env:USERPROFILE "Downloads\UiPath_temp\"
$folder_downloads = Join-Path $downloadFolder "\downloads"


# ---------- LOAD AND CLEAN XAML ----------
$xamlPath = Join-Path $downloadFolder "xaml_files\ConnectWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show("ConnectWindow.xaml not found after download.", "Error", "OK", "Error")
    exit
}

# Remove unsupported markup
$xamlRaw = Get-Content $xamlPath -Raw
$xamlClean = $xamlRaw -replace 'mc:Ignorable="[^"]*"', ''
$xamlClean = $xamlClean -replace 'xmlns:mc="[^"]*"', ''
[xml]$xaml = $xamlClean
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)


