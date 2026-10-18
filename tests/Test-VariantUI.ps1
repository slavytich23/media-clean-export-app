param([switch]$RestoreOnly, [string]$Sandbox)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Sandbox) { $Sandbox = Join-Path $projectRoot ('.scratch\ui-test-' + [guid]::NewGuid().ToString('N')) }
[void](New-Item -ItemType Directory -Force -Path $Sandbox)
$env:APPDATA = Join-Path $Sandbox 'appdata'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::SetUnhandledExceptionMode('ThrowException')
. (Join-Path $projectRoot 'MediaCleanExport.ps1') -NoShow
$script:variantAutoOpenPreview = $false

function Assert-UiTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Output "PASS: $Message"
}

function Wait-UiJob {
    $deadline = (Get-Date).AddSeconds(90)
    while ($script:variantBusy -and (Get-Date) -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        [System.Threading.Thread]::Sleep(20)
    }
    Assert-UiTest (-not $script:variantBusy) 'background job completes without blocking UI'
}

try {
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Assert-UiTest ($modeTabs.TabPages.Count -eq 2) 'both application modes exist'
    Assert-UiTest ($appCredit.Text -eq 'Powered by slavytich') 'exact footer text'
    Assert-UiTest ($appCredit.Links[0].LinkData -eq 'https://t.me/slavytich23') 'footer links to creator Telegram'
    if ($RestoreOnly) {
        Assert-UiTest ($settings.Theme -eq 'Light' -and $variantCount.Value -eq 2 -and $modeTabs.SelectedIndex -eq 1) 'theme, count and mode restored in a fresh process'
        return
    }
    $modeTabs.SelectedIndex = 1
    $variantAdvancedToggle.PerformClick()
    $themeDarkButton.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, $form.ClientRectangle)
    $bitmap.Save((Join-Path $Sandbox 'dark.png'))
    $bitmap.Dispose()
    Assert-UiTest ($appFooter.Bottom -le $form.ClientSize.Height -and $modeTabs.Bottom -le $appFooter.Top) 'footer stays outside scrollable tab content'
    $themeLightButton.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, $form.ClientRectangle)
    $bitmap.Save((Join-Path $Sandbox 'light.png'))
    $bitmap.Dispose()
    $variantCount.Value = 2
    $variantOutput.Text = $Sandbox
    $photo = Join-Path $Sandbox 'ui source.png'
    & $ffmpegPath -v error -f lavfi -i 'testsrc2=size=320x240' -frames:v 1 $photo
    if ($LASTEXITCODE) { throw 'UI fixture failed' }
    Add-VariantInputs @($photo)
    $sourceHash = (Get-FileHash -LiteralPath $photo).Hash
    Start-VariantRun
    Assert-UiTest ($script:variantBusy -and $variantCancel.Enabled -and -not $variantRun.Enabled) 'running controls and cancellation state'
    Wait-UiJob
    Assert-UiTest ($script:variantLastResult.Success -eq 2 -and $variantProgress.Value -eq 2) 'real background exports update UI progress'
    Assert-UiTest ($variantList.Items[0].SubItems[2].Text -eq '2 / 2') 'per-source count updates'
    Assert-UiTest ((Get-FileHash -LiteralPath $photo).Hash -eq $sourceHash) 'UI preserves original'
    Start-VariantRun -Preview
    Wait-UiJob
    Assert-UiTest ($script:variantLastResult.Success -eq 1 -and $variantOpenPreview.Enabled) 'preview ready state'
    $variantOpenPreview.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    Assert-UiTest ($form.OwnedForms.Count -eq 1 -and $form.OwnedForms[0].Controls[0].Image.Width -eq 320) 'photo preview opens a real image window'
    foreach ($previewWindow in @($form.OwnedForms)) { $previewWindow.Close() }
    $variantChecks.Tone.Checked = -not $variantChecks.Tone.Checked
    Assert-UiTest (-not $variantOpenPreview.Enabled) 'changed settings invalidate old preview'
    $variantChecks.Tone.Checked = $true
    $variantCount.Value = 100
    Start-VariantRun
    $deadline = (Get-Date).AddSeconds(10)
    while ($script:variantBusy -and (Get-Date) -lt $deadline -and -not ($script:variantState.Stage -eq 'Encoding' -and $script:variantState.ActiveProcessId)) {
        [System.Windows.Forms.Application]::DoEvents()
        [System.Threading.Thread]::Sleep(5)
    }
    Assert-UiTest ($script:variantBusy -and $script:variantState.ActiveProcessId) 'active native processing observed before cancellation'
    $variantCancel.PerformClick()
    Wait-UiJob
    Assert-UiTest ($script:variantLastResult.Cancelled -and $script:variantLastResult.Success -lt 100) 'stop button cancels an active batch'
    Assert-UiTest ($variantRun.Enabled -and -not $variantCancel.Enabled) 'controls recover after cancellation'
    $variantCount.Value = 2
    $stored = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    Assert-UiTest ($stored.Theme -eq 'Light' -and $stored.VariantOptions.Count -eq 2 -and $stored.LastMode -eq 'Variants') 'theme and variant options persisted'
    $modeTabs.SelectedIndex = 0
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, $form.ClientRectangle)
    $bitmap.Save((Join-Path $Sandbox 'metadata-light.png'))
    $bitmap.Dispose()
    $modeTabs.SelectedIndex = 1
    Write-Output "ARTIFACTS: $Sandbox"
} finally { $form.Close(); $form.Dispose() }
