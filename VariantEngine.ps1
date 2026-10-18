if (-not ('MediaCleanExport.VariantPixels' -as [type])) {
    Add-Type -TypeDefinition @'
namespace MediaCleanExport {
    public static class VariantPixels {
        public static double Distance(byte[] left, byte[] right) {
            if (left.Length != right.Length || left.Length == 0)
                throw new System.ArgumentException("Incompatible decoded samples.");
            long sum = 0;
            for (int i = 0; i < left.Length; i++) sum += System.Math.Abs((int)left[i] - right[i]);
            return (double)sum / left.Length;
        }
    }
}
'@
}

function Get-VariantDefaultOptions {
    return [pscustomobject]@{
        Count = 5; Strength = 'Gentle'; Crf = 18; PhotoFormat = 'Jpeg'
        Crop = $true; Tone = $true; Speed = $false; Trim = $false; Mirror = $false
        StripMetadata = $true; OutputDirectory = ''
    }
}

function Test-VariantOptions {
    param([psobject]$Options)
    if ($Options.Count -lt 1 -or $Options.Count -gt 1000) { throw 'Count must be between 1 and 1000 per source.' }
    if ($Options.Strength -notin @('Gentle', 'Expressive')) { throw 'Unknown strength.' }
    if ($Options.Crf -notin @(18, 20, 23)) { throw 'Unknown video quality.' }
    if ($Options.PhotoFormat -notin @('Jpeg', 'Png')) { throw 'Unknown photo format.' }
    if (-not ($Options.Crop -or $Options.Tone -or $Options.Speed -or $Options.Trim -or $Options.Mirror)) {
        throw 'Enable at least one content transformation.'
    }
}

function ConvertTo-VariantArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting, including backslashes before closing quotes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-VariantTool {
    param(
        [string]$Executable, [string[]]$Arguments, [hashtable]$State,
        [switch]$Binary
    )
    if ($State.CancelRequested) { throw [OperationCanceledException]::new('Cancelled') }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($Arguments | ForEach-Object { ConvertTo-VariantArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $memory = New-Object System.IO.MemoryStream
    try {
        [void]$process.Start()
        $State.ActiveProcessId = $process.Id
        $errorTask = $process.StandardError.ReadToEndAsync()
        if ($Binary) { $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($memory) }
        else { $outputTask = $process.StandardOutput.ReadToEndAsync() }
        while (-not $process.WaitForExit(100)) {
            if ($State.CancelRequested) {
                $process.Kill()
                $process.WaitForExit()
                [void]$outputTask.GetAwaiter().GetResult()
                [void]$errorTask.GetAwaiter().GetResult()
                throw [OperationCanceledException]::new('Cancelled')
            }
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $diagnostic = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Tool exited with code $($process.ExitCode): $diagnostic" }
        if ($Binary) { return [pscustomobject]@{ Bytes = $memory.ToArray() } }
        return [string]$output
    } finally {
        $State.ActiveProcessId = $null
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-VariantMediaInfo {
    param([string]$FilePath, [string]$FFprobePath, [hashtable]$State)
    $State.Stage = 'Probe'
    $json = Invoke-VariantTool $FFprobePath @('-v', 'error', '-show_streams', '-show_format', '-of', 'json', $FilePath) $State | ConvertFrom-Json
    $video = @($json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)
    if (-not $video.Count) { throw "No image/video stream: $FilePath" }
    $stream = $video[0]
    $kind = if ([IO.Path]::GetExtension($FilePath).ToLowerInvariant() -in @('.mp4', '.mov', '.m4v')) { 'Video' } else { 'Photo' }
    $duration = 0.0
    if ($kind -eq 'Video') {
        $duration = [double]::Parse([string]$json.format.duration, [Globalization.CultureInfo]::InvariantCulture)
        if ($duration -le 0) { throw 'Invalid video duration.' }
    }
    $rotation = 0
    foreach ($sideData in @($stream.side_data_list)) {
        if ($null -ne $sideData.rotation) { $rotation = [int]$sideData.rotation }
    }
    if ($stream.tags.rotate) { $rotation = [int]$stream.tags.rotate }
    $width = [int]$stream.width; $height = [int]$stream.height
    if ([Math]::Abs($rotation) % 180 -eq 90) { $width = [int]$stream.height; $height = [int]$stream.width }
    if ($width -lt 2 -or $height -lt 2) { throw 'Image is too small.' }
    $audio = @($json.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)
    $audioStart = 0.0; $audioDuration = 0.0; $formatStart = 0.0
    [void][double]::TryParse([string]$json.format.start_time, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$formatStart)
    if ($audio.Count) {
        [void][double]::TryParse([string]$audio[0].start_time, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$audioStart)
        [void][double]::TryParse([string]$audio[0].duration, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$audioDuration)
        $audioStart = [Math]::Max(0, $audioStart - $formatStart)
        if ($audioDuration -le 0) { $audioDuration = [Math]::Max(0, $duration - $audioStart) }
    }
    return [pscustomobject]@{
        Kind = $kind; Width = $width; Height = $height; Duration = $duration
        HasAudio = [bool]$audio.Count; AudioDuration = $audioDuration; AudioStart = $audioStart
    }
}

function Get-VariantSampleDistance {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length -or $Left.Length -eq 0) { throw 'Incompatible decoded samples.' }
    return [MediaCleanExport.VariantPixels]::Distance($Left, $Right)
}

function Get-VariantVisualSample {
    param([string]$FilePath, [psobject]$Info, [string]$FFmpegPath, [hashtable]$State)
    $State.Stage = 'Sampling'
    $sampleBytes = New-Object 'System.Collections.Generic.List[byte]'
    $positions = if ($Info.Kind -eq 'Video') { @(0.15, 0.50, 0.85) } else { @(0) }
    foreach ($position in $positions) {
        $arguments = @('-v', 'error', '-nostdin', '-threads', '1')
        if ($Info.Kind -eq 'Video') {
            $arguments += @('-ss', ($Info.Duration * $position).ToString('0.######', [Globalization.CultureInfo]::InvariantCulture))
        }
        $arguments += @('-i', $FilePath, '-map', '0:v:0', '-vf', 'scale=48:48:flags=area,format=rgb24', '-frames:v', '1', '-threads', '1', '-f', 'rawvideo', 'pipe:1')
        $raw = Invoke-VariantTool $FFmpegPath $arguments $State -Binary
        if ($raw.Bytes.Length -ne 6912) { throw 'Decoded visual sample is incomplete.' }
        $sampleBytes.AddRange([byte[]]$raw.Bytes)
    }
    return ,$sampleBytes.ToArray()
}

function New-VariantRecipe {
    param([psobject]$Info, [psobject]$Options, [int]$Seed)
    $random = New-Object System.Random($Seed)
    $strong = $Options.Strength -eq 'Expressive'
    $crop = if ($Options.Crop) { 0.01 + $random.NextDouble() * $(if ($strong) { 0.09 } else { 0.025 }) } else { 0 }
    $toneRange = if ($strong) { 0.075 } else { 0.025 }
    $brightness = 0.0; $contrast = 1.0; $saturation = 1.0; $warmth = 0.0
    if ($Options.Tone) {
        $brightness = ($random.NextDouble() * 2 - 1) * $toneRange
        $contrast = 1 + ($random.NextDouble() * 2 - 1) * $toneRange
        $saturation = 1 + ($random.NextDouble() * 2 - 1) * $toneRange * 1.5
        $warmth = ($random.NextDouble() * 2 - 1) * $toneRange * 0.5
    }
    $speed = 1.0; $trimStart = 0.0; $trimEnd = 0.0
    if ($Info.Kind -eq 'Video') {
        if ($Options.Speed) { $speed = 1 + ($random.NextDouble() * 2 - 1) * $(if ($strong) { 0.06 } else { 0.03 }) }
        if ($Options.Trim) {
            $trimLimit = [Math]::Min(0.5, $Info.Duration * 0.04)
            $trimStart = $random.NextDouble() * $trimLimit
            $trimEnd = $random.NextDouble() * $trimLimit
        }
    }
    $mirror = [bool]($Options.Mirror -and $random.Next(2) -eq 1)
    if ($Options.Mirror -and -not ($Options.Crop -or $Options.Tone -or ($Info.Kind -eq 'Video' -and ($Options.Speed -or $Options.Trim)))) { $mirror = $true }
    return [pscustomobject]@{
        Seed = $Seed; Crop = $crop; OffsetX = $random.NextDouble(); OffsetY = $random.NextDouble()
        Brightness = $brightness; Contrast = $contrast; Saturation = $saturation; Warmth = $warmth
        Speed = $speed; TrimStart = $trimStart; TrimEnd = $trimEnd
        Mirror = $mirror
    }
}

function Export-VariantMedia {
    param(
        [string]$InputPath, [string]$OutputPath, [psobject]$Info, [psobject]$Recipe,
        [psobject]$Options, [string]$FFmpegPath, [hashtable]$State,
        [switch]$Preview
    )
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $outputWidth = $Info.Width; $outputHeight = $Info.Height
    if ($Info.Kind -eq 'Video') {
        $outputWidth = [int]([Math]::Floor($outputWidth / 2) * 2)
        $outputHeight = [int]([Math]::Floor($outputHeight / 2) * 2)
    }
    $filters = New-Object 'System.Collections.Generic.List[string]'
    if ($Recipe.Crop -gt 0) {
        $cropWidth = [int][Math]::Max(2, [Math]::Floor($Info.Width * (1 - $Recipe.Crop) / 2) * 2)
        $cropHeight = [int][Math]::Max(2, [Math]::Floor($Info.Height * (1 - $Recipe.Crop) / 2) * 2)
        $cropX = [int]([Math]::Floor(($Info.Width - $cropWidth) * $Recipe.OffsetX / 2) * 2)
        $cropY = [int]([Math]::Floor(($Info.Height - $cropHeight) * $Recipe.OffsetY / 2) * 2)
        $filters.Add("crop=${cropWidth}:${cropHeight}:${cropX}:${cropY}")
    }
    $filters.Add("scale=${outputWidth}:${outputHeight}:flags=lanczos")
    $filters.Add('setsar=1')
    if ($Options.Tone) {
        $filters.Add(('eq=brightness={0}:contrast={1}:saturation={2}' -f $Recipe.Brightness.ToString('0.######', $culture), $Recipe.Contrast.ToString('0.######', $culture), $Recipe.Saturation.ToString('0.######', $culture)))
        $filters.Add(('colorbalance=rs={0}:bs={1}' -f $Recipe.Warmth.ToString('0.######', $culture), (-$Recipe.Warmth).ToString('0.######', $culture)))
    }
    if ($Recipe.Mirror) { $filters.Add('hflip') }
    if ($Info.Kind -eq 'Video') { $filters.Add(('setpts=PTS/{0}' -f $Recipe.Speed.ToString('0.######', $culture))) }
    $arguments = @('-v', 'error', '-nostdin', '-n')
    if ($Info.Kind -eq 'Video') { $arguments += @('-ss', $Recipe.TrimStart.ToString('0.######', $culture)) }
    $arguments += @('-i', $InputPath)
    $inputDuration = $Info.Duration - $Recipe.TrimStart - $Recipe.TrimEnd
    if ($Preview -and $Info.Kind -eq 'Video') { $inputDuration = [Math]::Min(5, $inputDuration) }
    if ($Info.Kind -eq 'Video') {
        $arguments += @('-t', ($inputDuration / $Recipe.Speed).ToString('0.######', $culture), '-map', '0:v:0', '-map', '0:a:0?')
    } else { $arguments += @('-map', '0:v:0', '-frames:v', '1') }
    $arguments += @('-map_metadata', $(if ($Options.StripMetadata) { '-1' } else { '0' }), '-map_chapters', '-1', '-vf', ($filters -join ','))
    if ($Info.Kind -eq 'Video') {
        $arguments += @('-c:v', 'libx264', '-preset', 'fast', '-crf', [string]$Options.Crf, '-pix_fmt', 'yuv420p', '-threads', '2', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-movflags', '+faststart')
        if ($Info.HasAudio) { $arguments += @('-af', ('atempo={0},asetpts=N/SR/TB+STARTPTS/{0}' -f $Recipe.Speed.ToString('0.######', $culture))) }
    } elseif ($Options.PhotoFormat -eq 'Png') { $arguments += @('-c:v', 'png', '-pix_fmt', 'rgba', '-threads', '1') }
    else { $arguments += @('-c:v', 'mjpeg', '-q:v', '2', '-pix_fmt', 'yuvj444p', '-threads', '1') }
    $arguments += $OutputPath
    $State.Stage = 'Encoding'
    [void](Invoke-VariantTool $FFmpegPath $arguments $State)
    $audioStart = [Math]::Max(0, $Info.AudioStart - $Recipe.TrimStart) / $Recipe.Speed
    $audioEnd = [Math]::Max(0, [Math]::Min(($Info.AudioStart + $Info.AudioDuration), ($Recipe.TrimStart + $inputDuration)) - $Recipe.TrimStart) / $Recipe.Speed
    return [pscustomobject]@{
        Width = $outputWidth; Height = $outputHeight; Duration = $inputDuration / $Recipe.Speed
        AudioStart = $audioStart; AudioDuration = [Math]::Max(0, $audioEnd - $audioStart)
        HasAudio = [bool]($Info.HasAudio -and $audioEnd -gt $audioStart)
    }
}

function Send-VariantEvent {
    param($Events, [string]$Type, [hashtable]$Data)
    $Data.Type = $Type
    if ($null -ne $Events) { $Events.Enqueue([pscustomobject]$Data) }
}

function Invoke-VariantBatch {
    param(
        [string[]]$InputPaths, [psobject]$Options, [string]$FFmpegPath,
        [string]$FFprobePath, [hashtable]$State, $Events, [switch]$Preview
    )
    Test-VariantOptions $Options
    $InputPaths = @($InputPaths | Select-Object -Unique)
    if (-not $InputPaths.Count) { throw 'No source files.' }
    if ($Preview) { $InputPaths = @($InputPaths[0]) }
    if (-not (Test-Path -LiteralPath $Options.OutputDirectory -PathType Container)) { throw 'Choose an existing output folder.' }
    if (-not (Test-Path -LiteralPath $FFmpegPath -PathType Leaf) -or -not (Test-Path -LiteralPath $FFprobePath -PathType Leaf)) { throw 'FFmpeg and FFprobe are required.' }
    $count = if ($Preview) { 1 } else { [int]$Options.Count }
    $jobDirectory = Join-Path $Options.OutputDirectory (('variants_{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8)))
    [void](New-Item -ItemType Directory -Path $jobDirectory)
    $manifestPath = Join-Path $jobDirectory 'manifest.json'
    $items = New-Object 'System.Collections.Generic.List[object]'
    $manifest = [ordered]@{
        Version = 1; Created = (Get-Date).ToString('o'); Preview = [bool]$Preview
        Requested = $InputPaths.Count * $count; Options = $Options
        SampleMethod = 'RGB 48x48 mean absolute difference; photos: one frame; video: 15%, 50%, 85%'
        MinimumDistance = 0.45; Status = 'Running'; Items = $items
    }
    $success = 0; $failed = 0; $cancelled = $false; $previewPath = $null
    Send-VariantEvent $Events 'Started' @{ Total = $manifest.Requested; Directory = $jobDirectory }
    try {
        $sourceNumber = 0
        foreach ($source in $InputPaths) {
            if ($State.CancelRequested) { throw [OperationCanceledException]::new('Cancelled') }
            $sourceNumber++
            $sourceItemsBefore = $items.Count
            try {
                $info = Get-VariantMediaInfo $source $FFprobePath $State
                if ($info.Kind -eq 'Photo' -and -not ($Options.Crop -or $Options.Tone -or $Options.Mirror)) { throw 'Photos require an image transformation.' }
                $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
                $sourceSamples = Get-VariantVisualSample $source $info $FFmpegPath $State
                $samples = New-Object 'System.Collections.Generic.List[object]'
                $samples.Add($sourceSamples)
                $recipes = New-Object 'System.Collections.Generic.HashSet[string]'
                $baseName = [IO.Path]::GetFileNameWithoutExtension($source)
                $sourceDirectory = Join-Path $jobDirectory ('{0:D3}_{1}' -f $sourceNumber, $baseName)
                [void](New-Item -ItemType Directory -Path $sourceDirectory)
                $workDirectory = Join-Path $sourceDirectory '.incomplete'
                $workFolder = New-Item -ItemType Directory -Path $workDirectory
                $workFolder.Attributes = $workFolder.Attributes -bor [IO.FileAttributes]::Hidden
                $extension = if ($info.Kind -eq 'Video') { '.mp4' } elseif ($Options.PhotoFormat -eq 'Png') { '.png' } else { '.jpg' }
                for ($index = 1; $index -le $count; $index++) {
                    if ($State.CancelRequested) { throw [OperationCanceledException]::new('Cancelled') }
                    $accepted = $false
                    for ($attempt = 1; $attempt -le 12; $attempt++) {
                        $seed = [BitConverter]::ToInt32([guid]::NewGuid().ToByteArray(), 0) -band 0x7fffffff
                        $recipe = New-VariantRecipe $info $Options $seed
                        $recipeKey = $recipe | Select-Object * -ExcludeProperty Seed | ConvertTo-Json -Compress
                        if (-not $recipes.Add($recipeKey)) { continue }
                        Send-VariantEvent $Events 'Working' @{ Source = $source; Index = $index; Attempt = $attempt; Done = $success; Total = $manifest.Requested }
                        $candidatePath = Join-Path $workDirectory ('{0:D4}_attempt{1:D2}{2}' -f $index, $attempt, $extension)
                        $expected = Export-VariantMedia $source $candidatePath $info $recipe $Options $FFmpegPath $State -Preview:$Preview
                        $outputInfo = Get-VariantMediaInfo $candidatePath $FFprobePath $State
                        if ($outputInfo.Width -ne $expected.Width -or $outputInfo.Height -ne $expected.Height) { throw 'Output dimension validation failed.' }
                        if ($info.Kind -eq 'Video') {
                            if ($expected.HasAudio -ne $outputInfo.HasAudio -or [Math]::Abs($expected.Duration - $outputInfo.Duration) -gt 0.35) { throw 'Output audio/duration validation failed.' }
                            if ($expected.HasAudio -and ([Math]::Abs($expected.AudioStart - $outputInfo.AudioStart) -gt 0.15 -or [Math]::Abs($expected.AudioDuration - $outputInfo.AudioDuration) -gt 0.35)) { throw 'Output audio synchronization validation failed.' }
                        }
                        $outputSamples = Get-VariantVisualSample $candidatePath $outputInfo $FFmpegPath $State
                        $minimumDistance = [double]::MaxValue
                        foreach ($previous in $samples) {
                            $distance = Get-VariantSampleDistance $previous $outputSamples
                            $minimumDistance = [Math]::Min($minimumDistance, $distance)
                        }
                        if ($minimumDistance -lt $manifest.MinimumDistance) { continue }
                        $finalPath = Join-Path $sourceDirectory ('{0}_{1:D4}{2}' -f $baseName, $index, $extension)
                        Move-Item -LiteralPath $candidatePath -Destination $finalPath -ErrorAction Stop
                        $samples.Add($outputSamples)
                        $item = [pscustomobject]@{
                            Source = $source; SourceHash = $sourceHash; Index = $index; Status = 'Done'; Path = $finalPath
                            Hash = (Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash
                            MinVisualDistance = $minimumDistance; Recipe = $recipe; Attempts = $attempt
                        }
                        $items.Add($item); $success++; $accepted = $true
                        if ($Preview) { $previewPath = $finalPath }
                        Send-VariantEvent $Events 'Done' @{ Item = $item; Done = $success; Total = $manifest.Requested }
                        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
                        break
                    }
                    if (-not $accepted) { throw 'Not enough visual diversity within the selected limits (12 attempts). Enable more transformations or reduce count.' }
                }
                if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Source was modified by another process during the job.' }
            } catch [OperationCanceledException] { throw }
            catch {
                $missing = $count - ($items.Count - $sourceItemsBefore)
                $failed += $missing
                $errorItem = [pscustomobject]@{ Source = $source; Status = 'Failed'; Missing = $missing; Error = $_.Exception.Message }
                $items.Add($errorItem)
                Send-VariantEvent $Events 'Failed' @{ Item = $errorItem; Done = $success; Total = $manifest.Requested }
            }
        }
    } catch [OperationCanceledException] { $cancelled = $true }
    finally {
        $manifest.Status = if ($cancelled) { 'Cancelled' } elseif ($failed) { 'Partial' } else { 'Done' }
        $manifest.Success = $success; $manifest.Failed = $failed
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }
    return [pscustomobject]@{
        Success = $success; Failed = $failed; Cancelled = $cancelled; Requested = $manifest.Requested
        Directory = $jobDirectory; ManifestPath = $manifestPath; PreviewPath = $previewPath
    }
}
