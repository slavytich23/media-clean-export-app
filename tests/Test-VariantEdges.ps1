$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:LANG = 'C'; $env:LC_ALL = 'C'; $env:LC_CTYPE = 'C'
. (Join-Path $projectRoot 'VariantEngine.ps1')
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$exiftool = 'C:\Users\Slava\AppData\Local\Programs\ExifTool\ExifTool.exe'
$runRoot = Join-Path $projectRoot ('.scratch\edges-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $runRoot)

function Assert-Edge {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Output "PASS: $Message"
}

function New-EdgeFixture {
    param([string[]]$Arguments)
    & $ffmpeg @Arguments
    if ($LASTEXITCODE) { throw 'Fixture creation failed' }
}

$photo = Join-Path $runRoot 'фото [1] & $test.png'
$video = Join-Path $runRoot 'long.mp4'
New-EdgeFixture @('-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=321x241:rate=1', '-frames:v', '1', $photo)
New-EdgeFixture @('-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '12', '-c:v', 'libx264', '-c:a', 'aac', '-pix_fmt', 'yuv420p', $video)
$state = [hashtable]::Synchronized(@{ CancelRequested = $false })
$events = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$options = Get-VariantDefaultOptions
$options.Count = 20
$options.OutputDirectory = $runRoot
$many = Invoke-VariantBatch @($photo, $video) $options $ffmpeg $ffprobe $state $events
Assert-Edge ($many.Success -eq 40 -and $many.Failed -eq 0) '20 verified variants for each source, including Unicode/metacharacter paths'
$manyManifest = Get-Content -Raw -LiteralPath $many.ManifestPath | ConvertFrom-Json
Assert-Edge (@($manyManifest.Items | Where-Object Status -eq 'Done' | Group-Object Hash | Where-Object Count -gt 1).Count -eq 0) 'all 40 files have distinct hashes'
$oddPhoto = Get-VariantMediaInfo (@($manyManifest.Items | Where-Object { $_.Path -like '*.jpg' })[0].Path) $ffprobe $state
Assert-Edge ($oddPhoto.Width -eq 321 -and $oddPhoto.Height -eq 241) 'odd photo dimensions preserved'

$rotated = Join-Path $runRoot 'rotated.mov'
New-EdgeFixture @('-v', 'error', '-display_rotation:v:0', '90', '-i', $video, '-c', 'copy', $rotated)
$rotatedInfo = Get-VariantMediaInfo $rotated $ffprobe $state
Assert-Edge ($rotatedInfo.Width -eq 240 -and $rotatedInfo.Height -eq 320) 'fixture has a real display rotation matrix'
$options.Count = 1
$options.Speed = $true
$options.Trim = $true
$options.Strength = 'Expressive'
$portrait = Invoke-VariantBatch @($rotated) $options $ffmpeg $ffprobe $state $events
Assert-Edge ($portrait.Success -eq 1) 'rotated video with speed and trim'
$portraitManifest = Get-Content -Raw -LiteralPath $portrait.ManifestPath | ConvertFrom-Json
$portraitInfo = Get-VariantMediaInfo $portraitManifest.Items[0].Path $ffprobe $state
Assert-Edge ($portraitInfo.Width -eq 240 -and $portraitInfo.Height -eq 320) 'display rotation honored without distortion'
$preview = Invoke-VariantBatch @($video) $options $ffmpeg $ffprobe $state $events -Preview
$previewInfo = Get-VariantMediaInfo $preview.PreviewPath $ffprobe $state
Assert-Edge ($preview.Success -eq 1 -and $previewInfo.Duration -lt 5.7) 'long video preview is limited to a short fragment'

$private = Join-Path $runRoot 'private.jpg'
New-EdgeFixture @('-v', 'error', '-i', $photo, '-frames:v', '1', $private)
& $exiftool -overwrite_original '-Make=Private Device' '-Model=Private Model' '-GPSLatitude=34' '-GPSLatitudeRef=N' '-GPSLongitude=118' '-GPSLongitudeRef=W' $private | Out-Null
if ($LASTEXITCODE) { throw 'Metadata fixture failed' }
$options.Speed = $false
$options.Trim = $false
$privateResult = Invoke-VariantBatch @($private) $options $ffmpeg $ffprobe $state $events
Assert-Edge ($privateResult.Success -eq 1) 'tagged source exported'
$privateManifest = Get-Content -Raw -LiteralPath $privateResult.ManifestPath | ConvertFrom-Json
$metadata = (& $exiftool -json -Make -Model -GPSLatitude -GPSLongitude $privateManifest.Items[0].Path | ConvertFrom-Json)[0]
Assert-Edge (-not $metadata.Make -and -not $metadata.Model -and -not $metadata.GPSLatitude -and -not $metadata.GPSLongitude) 'personal device and GPS tags removed'
$badSource = Join-Path $runRoot 'corrupt.png'
'not a media file' | Set-Content -LiteralPath $badSource
$partial = Invoke-VariantBatch @($badSource, $photo) $options $ffmpeg $ffprobe $state $events
Assert-Edge ($partial.Success -eq 1 -and $partial.Failed -eq 1) 'bad source does not stop remaining sources or count as success'

$nativeState = [hashtable]::Synchronized(@{ CancelRequested = $false })
$worker = [powershell]::Create()
[void]$worker.AddScript({
    param($Engine, $FFmpeg, $State)
    . $Engine
    try {
        [void](Invoke-VariantTool $FFmpeg @('-v', 'error', '-nostdin', '-re', '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=24', '-t', '30', '-f', 'null', '-') $State)
        return 'Unexpected completion'
    } catch [OperationCanceledException] { return 'Cancelled' }
}).AddArgument((Join-Path $projectRoot 'VariantEngine.ps1')).AddArgument($ffmpeg).AddArgument($nativeState)
try {
    $async = $worker.BeginInvoke()
    $deadline = (Get-Date).AddSeconds(5)
    while (-not $nativeState.ActiveProcessId -and (Get-Date) -lt $deadline) { [System.Threading.Thread]::Sleep(10) }
    Assert-Edge ([bool]$nativeState.ActiveProcessId) 'native process is running before cancel'
    $nativeProcess = [System.Diagnostics.Process]::GetProcessById($nativeState.ActiveProcessId)
    $nativeState.CancelRequested = $true
    $completed = $async.AsyncWaitHandle.WaitOne(5000)
    Assert-Edge $completed 'active FFmpeg stops within five seconds'
    $cancelResult = @($worker.EndInvoke($async))
    Assert-Edge ($cancelResult[-1] -eq 'Cancelled' -and $nativeProcess.HasExited) 'cancel stops only the task-owned FFmpeg process'
    $nativeProcess.Dispose()
} finally { $worker.Dispose() }
Write-Output "ARTIFACTS: $runRoot"
