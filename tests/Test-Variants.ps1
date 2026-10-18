param([switch]$CoreOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'VariantEngine.ps1')

function Assert-VariantTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Output "PASS: $Message"
}

$defaults = Get-VariantDefaultOptions
Assert-VariantTest ($defaults.Count -eq 5 -and -not $defaults.Speed -and -not $defaults.Trim -and -not $defaults.Mirror) 'safe defaults'
$sampleA = [byte[]](0, 20, 40, 60, 80, 100)
$sampleB = [byte[]](1, 21, 41, 61, 81, 101)
Assert-VariantTest ((Get-VariantSampleDistance $sampleA $sampleA) -eq 0) 'identical decoded samples are duplicates'
Assert-VariantTest ((Get-VariantSampleDistance $sampleA $sampleB) -eq 1) 'decoded sample distance measures image differences'
$invalid = Get-VariantDefaultOptions
$invalid.Crop = $false
$invalid.Tone = $false
$rejected = $false
try { Test-VariantOptions $invalid } catch { $rejected = $true }
Assert-VariantTest $rejected 'all transformations disabled is rejected'
$mirrorOptions = Get-VariantDefaultOptions
$mirrorOptions.Crop = $false
$mirrorOptions.Tone = $false
$mirrorOptions.Mirror = $true
$mirrorRecipe = New-VariantRecipe -Info ([pscustomobject]@{Kind='Photo'}) -Options $mirrorOptions -Seed 10
Assert-VariantTest $mirrorRecipe.Mirror 'mirror-only mode always performs its enabled transformation'
if ($CoreOnly) { return }

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$runRoot = Join-Path $projectRoot ('.scratch\variants-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $runRoot)
$photo = Join-Path $runRoot 'test photo.png'
$video = Join-Path $runRoot 'test video.mp4'
$silent = Join-Path $runRoot 'silent.mp4'
& $ffmpeg -v error -f lavfi -i 'testsrc2=size=320x240:rate=24' -frames:v 1 $photo
if ($LASTEXITCODE) { throw 'Photo fixture failed' }
& $ffmpeg -v error -f lavfi -i 'testsrc2=size=320x240:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $video
if ($LASTEXITCODE) { throw 'Video fixture failed' }
& $ffmpeg -v error -i $video -c:v copy -an $silent
if ($LASTEXITCODE) { throw 'Silent fixture failed' }
$originalHashes = @{}
foreach ($path in @($photo, $video, $silent)) { $originalHashes[$path] = (Get-FileHash -LiteralPath $path).Hash }
$options = Get-VariantDefaultOptions
$options.Count = 3
$options.OutputDirectory = $runRoot
$state = [hashtable]::Synchronized(@{ CancelRequested = $false })
$events = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$result = Invoke-VariantBatch -InputPaths @($photo, $video) -Options $options -FFmpegPath $ffmpeg -FFprobePath $ffprobe -State $state -Events $events
Assert-VariantTest ($result.Success -eq 6 -and $result.Failed -eq 0) 'N outputs per photo and video'
Assert-VariantTest (Test-Path -LiteralPath $result.ManifestPath) 'manifest exists'
$manifest = Get-Content -Raw -LiteralPath $result.ManifestPath | ConvertFrom-Json
$outputs = @($manifest.Items | Where-Object Status -eq 'Done')
Assert-VariantTest ($outputs.Count -eq 6) 'only verified outputs count as done'
Assert-VariantTest (@($outputs | Group-Object Hash | Where-Object Count -gt 1).Count -eq 0) 'no byte-identical output duplicates'
foreach ($item in $outputs) {
    Assert-VariantTest ($item.MinVisualDistance -ge 0.45) "verified visual difference: $([IO.Path]::GetFileName($item.Path))"
    $info = Get-VariantMediaInfo -FilePath $item.Path -FFprobePath $ffprobe -State $state
    Assert-VariantTest ($info.Width -eq 320 -and $info.Height -eq 240) 'dimensions preserved'
    if ($info.Kind -eq 'Video') { Assert-VariantTest ($info.HasAudio -and [Math]::Abs($info.Duration - 2) -lt 0.35) 'audio and duration preserved' }
}
$options.Count = 1
$options.Speed = $true
$options.Trim = $true
$options.PhotoFormat = 'Png'
$advanced = Invoke-VariantBatch -InputPaths @($photo, $video, $silent) -Options $options -FFmpegPath $ffmpeg -FFprobePath $ffprobe -State $state -Events $events
Assert-VariantTest ($advanced.Success -eq 3) 'PNG, speed/trim, and silent video'
$preview = Invoke-VariantBatch -InputPaths @($video) -Options $options -FFmpegPath $ffmpeg -FFprobePath $ffprobe -State $state -Events $events -Preview
Assert-VariantTest ($preview.Success -eq 1 -and $preview.Requested -eq 1) 'preview renders one video fragment'
$flat = Join-Path $runRoot 'flat.png'
& $ffmpeg -v error -f lavfi -i 'color=white:size=64x64' -frames:v 1 $flat
$options.Speed = $false
$options.Trim = $false
$options.Tone = $false
$options.Crop = $true
$impossible = Invoke-VariantBatch -InputPaths @($flat) -Options $options -FFmpegPath $ffmpeg -FFprobePath $ffprobe -State $state -Events $events
Assert-VariantTest ($impossible.Success -eq 0 -and $impossible.Failed -eq 1) 'insufficient image diversity reports a shortfall'
$state.CancelRequested = $true
$cancelled = Invoke-VariantBatch -InputPaths @($video) -Options $options -FFmpegPath $ffmpeg -FFprobePath $ffprobe -State $state -Events $events
Assert-VariantTest ($cancelled.Cancelled -and $cancelled.Success -eq 0) 'cancellation does not mark unfinished work successful'
foreach ($path in @($photo, $video, $silent)) { Assert-VariantTest ((Get-FileHash -LiteralPath $path).Hash -eq $originalHashes[$path]) 'source hash unchanged' }
Write-Output "ARTIFACTS: $runRoot"
