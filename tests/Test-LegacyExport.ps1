$ErrorActionPreference = 'Stop'
$env:LANG = 'C'; $env:LC_ALL = 'C'; $env:LC_CTYPE = 'C'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $projectRoot ('.scratch\legacy-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $runRoot)
$env:APPDATA = Join-Path $runRoot 'appdata'
. (Join-Path $projectRoot 'MediaCleanExport.ps1') -NoShow
function Assert-Legacy {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Output "PASS: $Message"
}
try {
    $photo = Join-Path $runRoot 'source.jpg'
    $video = Join-Path $runRoot 'source.mp4'
    & $ffmpegPath -v error -f lavfi -i 'testsrc2=size=320x240:rate=24' -frames:v 1 $photo
    if ($LASTEXITCODE) { throw 'Photo fixture failed' }
    & $ffmpegPath -v error -f lavfi -i 'testsrc2=size=320x240:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 1 -c:v libx264 -c:a aac $video
    if ($LASTEXITCODE) { throw 'Video fixture failed' }
    $photoHash = (Get-FileHash -LiteralPath $photo).Hash
    $videoHash = (Get-FileHash -LiteralPath $video).Hash
    $profile = Get-SelectedProfile
    $photoOutput = Join-Path $runRoot 'copy.jpg'
    [void](Copy-PhotoWithMetadata -InputPath $photo -OutputPath $photoOutput -Profile $profile -Latitude 34.05223 -Longitude -118.24368)
    $metadata = (& $exifToolPath -json -Model -GPSLatitude -GPSLongitude $photoOutput | ConvertFrom-Json)[0]
    Assert-Legacy ($metadata.Model -eq $profile.Model -and $metadata.GPSLatitude -and $metadata.GPSLongitude) 'legacy photo device and GPS readback'
    foreach ($mode in @('Compatible', 'Remux')) {
        $output = Join-Path $runRoot ($mode + '.mp4')
        $result = Export-CleanVideo -InputPath $video -OutputPath $output -Crf 18 -Profile $profile -Latitude 34.05223 -Longitude -118.24368 -Mode $mode
        Assert-Legacy ($result.Width -eq 320 -and $result.Height -eq 240 -and $result.HasAudio -and $result.Device -eq $profile.Display -and $result.GpsCoordinates) ('legacy video checks: ' + $mode)
    }
    Assert-Legacy ((Get-FileHash -LiteralPath $photo).Hash -eq $photoHash -and (Get-FileHash -LiteralPath $video).Hash -eq $videoHash) 'legacy copy mode preserves originals'
    Write-Output "ARTIFACTS: $runRoot"
} finally { $form.Dispose(); $variantTimer.Dispose() }
