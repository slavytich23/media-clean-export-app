$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'VariantEngine.ps1')
$ffmpeg = (Get-Command ffmpeg).Source
$ffprobe = (Get-Command ffprobe).Source
$runRoot = Join-Path $projectRoot ('.scratch\audio-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $runRoot)
$state = [hashtable]::Synchronized(@{ CancelRequested = $false })
$events = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$options = Get-VariantDefaultOptions
$options.Count = 1
$options.OutputDirectory = $runRoot
foreach ($offset in @(0, 0.5)) {
    $source = Join-Path $runRoot ('audio-offset-' + [string]$offset + '.mp4')
    $offsetText = $offset.ToString([Globalization.CultureInfo]::InvariantCulture)
    & $ffmpeg -v error -f lavfi -i 'testsrc2=size=320x240:rate=24' -itsoffset $offsetText -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=0.7' -t 2 -c:v libx264 -c:a aac $source
    if ($LASTEXITCODE) { throw 'Audio fixture failed' }
    foreach ($speedEnabled in @($false, $true)) {
        $options.Speed = $speedEnabled
        $result = Invoke-VariantBatch @($source) $options $ffmpeg $ffprobe $state $events
        if ($result.Success -ne 1) { throw "FAIL: short/delayed audio rejected: offset=$offset speed=$speedEnabled" }
        $manifest = Get-Content -Raw -LiteralPath $result.ManifestPath | ConvertFrom-Json
        $sourceJson = & $ffprobe -v error -show_streams -of json $source | ConvertFrom-Json
        $outputJson = & $ffprobe -v error -show_streams -of json $manifest.Items[0].Path | ConvertFrom-Json
        $sourceAudio = @($sourceJson.streams | Where-Object codec_type -eq 'audio')[0]
        $outputAudio = @($outputJson.streams | Where-Object codec_type -eq 'audio')[0]
        $speed = $manifest.Items[0].Recipe.Speed
        $expectedStart = [double]::Parse($sourceAudio.start_time, [Globalization.CultureInfo]::InvariantCulture) / $speed
        $actualStart = [double]::Parse($outputAudio.start_time, [Globalization.CultureInfo]::InvariantCulture)
        if ([Math]::Abs($expectedStart - $actualStart) -gt 0.12) { throw 'FAIL: relative audio start was shifted' }
        Write-Output "PASS: short/delayed audio and sync: offset=$offset speed=$speedEnabled"
    }
}
Write-Output "ARTIFACTS: $runRoot"
