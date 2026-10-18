param(
    [switch]$TestMode,
    [switch]$NoShow
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$profileCatalogPath = Join-Path $scriptRoot 'DeviceProfiles.json'
$settingsDirectory = Join-Path $env:APPDATA 'MediaCleanExport'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
. (Join-Path $scriptRoot 'VariantEngine.ps1')
. (Join-Path $scriptRoot 'AppControls.ps1')

$photoExtensions = @('.jpg', '.jpeg', '.png', '.heic', '.heif', '.tif', '.tiff', '.webp')
$videoExtensions = @('.mp4', '.mov', '.m4v')
$mediaExtensions = $photoExtensions + $videoExtensions

function Get-DefaultSettings {
    return [pscustomobject]@{
        LastDeviceId = 'apple-iphone-16-pro'
        LastCustomMake = 'My phone'
        LastCustomModel = 'Custom model'
        LastCustomLensModel = 'Rear camera'
        LastLensModel = ''
        LastLatitude = '34.052230'
        LastLongitude = '-118.243680'
        LastCrf = 18
        VideoMode = 'Compatible'
        BackupEnabled = $true
        KeepOriginals = $true
        NeutralNames = $true
        FavoriteDeviceIds = @('apple-iphone-16-pro')
        LastOutputDirectory = ''
        LastMode = 'Metadata'
        Theme = 'Dark'
        VariantOptions = Get-VariantDefaultOptions
    }
}

function Load-Settings {
    $settings = Get-DefaultSettings
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        return $settings
    }

    try {
        $stored = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($stored.LastDeviceId) { $settings.LastDeviceId = [string]$stored.LastDeviceId }
        if ($stored.LastCustomMake) { $settings.LastCustomMake = [string]$stored.LastCustomMake }
        if ($stored.LastCustomModel) { $settings.LastCustomModel = [string]$stored.LastCustomModel }
        if ($stored.LastCustomLensModel) { $settings.LastCustomLensModel = [string]$stored.LastCustomLensModel }
        if ($stored.LastLensModel) { $settings.LastLensModel = [string]$stored.LastLensModel }
        if ($stored.LastLatitude) { $settings.LastLatitude = [string]$stored.LastLatitude }
        if ($stored.LastLongitude) { $settings.LastLongitude = [string]$stored.LastLongitude }
        if ($null -ne $stored.LastCrf) { $settings.LastCrf = [int]$stored.LastCrf }
        if ($stored.VideoMode) { $settings.VideoMode = [string]$stored.VideoMode }
        if ($null -ne $stored.BackupEnabled) { $settings.BackupEnabled = [bool]$stored.BackupEnabled }
        if ($null -ne $stored.KeepOriginals) { $settings.KeepOriginals = [bool]$stored.KeepOriginals }
        if ($null -ne $stored.NeutralNames) { $settings.NeutralNames = [bool]$stored.NeutralNames }
        if ($null -ne $stored.FavoriteDeviceIds) {
            $settings.FavoriteDeviceIds = @($stored.FavoriteDeviceIds | ForEach-Object { [string]$_ })
        }
        if ($stored.LastOutputDirectory) { $settings.LastOutputDirectory = [string]$stored.LastOutputDirectory }
        if ($stored.LastMode -in @('Metadata', 'Variants')) { $settings.LastMode = [string]$stored.LastMode }
        if ($stored.Theme -in @('Light', 'Dark')) { $settings.Theme = [string]$stored.Theme }
        if ($stored.VariantOptions) {
            foreach ($property in $settings.VariantOptions.PSObject.Properties) {
                $savedProperty = $stored.VariantOptions.PSObject.Properties[$property.Name]
                if ($null -ne $savedProperty) { $property.Value = $savedProperty.Value }
            }
            try { Test-VariantOptions $settings.VariantOptions }
            catch { $settings.VariantOptions = Get-VariantDefaultOptions }
        }
    } catch {
        # A damaged settings file must not prevent the application from opening.
        $settings = Get-DefaultSettings
    }

    return $settings
}

function Save-Settings {
    param([Parameter(Mandatory)] [psobject]$Settings)

    try {
        New-Item -ItemType Directory -Force -Path $settingsDirectory | Out-Null
        $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Load-DeviceProfiles {
    if (-not (Test-Path -LiteralPath $profileCatalogPath -PathType Leaf)) {
        throw "Device catalog not found: $profileCatalogPath"
    }

    $profiles = @(Get-Content -LiteralPath $profileCatalogPath -Raw | ConvertFrom-Json)
    if ($profiles.Count -eq 0) {
        throw 'Device catalog is empty.'
    }

    $duplicateIds = @($profiles | Group-Object -Property Id | Where-Object { $_.Count -gt 1 })
    if ($duplicateIds.Count -gt 0) {
        throw "Device catalog contains duplicate IDs: $($duplicateIds.Name -join ', ')"
    }

    return @($profiles | Sort-Object GroupOrder, Display)
}

function Find-CommandPath {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string[]]$Candidates = @()
    )

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

$ffmpegPath = Find-CommandPath -Name 'ffmpeg' -Candidates @(
    (Join-Path $scriptRoot 'tools\ffmpeg\bin\ffmpeg.exe'),
    (Join-Path $scriptRoot 'ffmpeg\bin\ffmpeg.exe'),
    'O:\TOOLS\FFmpeg\ffmpeg-8.1.2-full_build-shared\bin\ffmpeg.exe'
)
$ffprobePath = Find-CommandPath -Name 'ffprobe' -Candidates @(
    (Join-Path $scriptRoot 'tools\ffmpeg\bin\ffprobe.exe'),
    (Join-Path $scriptRoot 'ffmpeg\bin\ffprobe.exe'),
    'O:\TOOLS\FFmpeg\ffmpeg-8.1.2-full_build-shared\bin\ffprobe.exe'
)
$exifToolPath = Find-CommandPath -Name 'exiftool' -Candidates @(
    (Join-Path $scriptRoot 'tools\exiftool\exiftool.exe'),
    (Join-Path $scriptRoot 'tools\exiftool\exiftool(-k).exe'),
    (Join-Path $scriptRoot 'tools\exiftool.exe'),
    (Join-Path $scriptRoot 'tools\exiftool(-k).exe'),
    'C:\Users\Slava\AppData\Local\Programs\ExifTool\ExifTool.exe'
)

$settings = Load-Settings
$deviceProfiles = Load-DeviceProfiles
$customProfile = [pscustomobject]@{
    Id = 'custom'
    Display = '✎ Свой телефон...'
    Make = $settings.LastCustomMake
    Model = $settings.LastCustomModel
    LensModel = $settings.LastCustomLensModel
    GroupOrder = 999
}
$script:allDeviceProfiles = @($deviceProfiles + $customProfile)
$deviceProfiles = $script:allDeviceProfiles
$script:visibleDeviceProfiles = $script:allDeviceProfiles

if ($TestMode) {
    $defaultIndex = 0
    for ($i = 0; $i -lt $deviceProfiles.Count; $i++) {
        if ($deviceProfiles[$i].Id -eq $settings.LastDeviceId) {
            $defaultIndex = $i
            break
        }
    }

    $duplicateCount = @($deviceProfiles | Group-Object -Property Id | Where-Object { $_.Count -gt 1 }).Count
    Write-Output "Profiles: $($script:allDeviceProfiles.Count)"
    Write-Output 'CustomProfile: available'
    Write-Output "DuplicateIds: $duplicateCount"
    Write-Output "DefaultDevice: $($deviceProfiles[$defaultIndex].Display)"
    Write-Output "ExifTool: $(if ($exifToolPath) { 'found' } else { 'missing' })"
    Write-Output "FFmpeg: $(if ($ffmpegPath) { 'found' } else { 'missing' })"
    Write-Output "FFprobe: $(if ($ffprobePath) { 'found' } else { 'missing' })"
    Write-Output "FFmpegPath: $ffmpegPath"
    Write-Output "FFprobePath: $ffprobePath"
    Write-Output "ExifToolPath: $exifToolPath"
    Write-Output "SettingsPath: $settingsPath"
    exit 0
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)] [string]$Executable,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    $localeNames = @('LANG', 'LC_ALL', 'LC_CTYPE')
    $savedLocale = @{}
    foreach ($localeName in $localeNames) {
        $savedLocale[$localeName] = [Environment]::GetEnvironmentVariable($localeName, 'Process')
        [Environment]::SetEnvironmentVariable($localeName, 'C', 'Process')
    }

    $savedErrorActionPreference = $ErrorActionPreference
    try {
        # Native tools use stderr for normal diagnostics and progress.
        $ErrorActionPreference = 'Continue'
        $output = & $Executable @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
        foreach ($localeName in $localeNames) {
            [Environment]::SetEnvironmentVariable($localeName, $savedLocale[$localeName], 'Process')
        }
    }

    if ($exitCode -ne 0) {
        $details = $output.Trim()
        if (-not $details) {
            $details = 'No diagnostic output.'
        }
        throw "Command failed with exit code $exitCode.`r`n$details"
    }

    return $output.Trim()
}

function Get-SupportedFiles {
    param([string[]]$Paths)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $mediaExtensions -contains $_.Extension.ToLowerInvariant()
            } | ForEach-Object {
                $result.Add($_.FullName)
            }
        } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path
            if ($mediaExtensions -contains $item.Extension.ToLowerInvariant()) {
                $result.Add($item.FullName)
            }
        }
    }

    return @($result | Select-Object -Unique)
}

function Get-MediaKind {
    param([Parameter(Mandatory)] [string]$FilePath)

    if ($videoExtensions -contains ([IO.Path]::GetExtension($FilePath).ToLowerInvariant())) {
        return 'Video'
    }
    return 'Photo'
}

function Convert-ToQuickTimeGps {
    param(
        [double]$Latitude,
        [double]$Longitude
    )

    $latSign = if ($Latitude -ge 0) { '+' } else { '-' }
    $lonSign = if ($Longitude -ge 0) { '+' } else { '-' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $lat = [Math]::Abs($Latitude).ToString('0.000000', $culture)
    $lon = [Math]::Abs($Longitude).ToString('0.000000', $culture)
    return "$latSign$lat$lonSign$lon/"
}

function Invoke-ExifToolForPhoto {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [double]$Latitude,
        [Parameter(Mandatory)] [double]$Longitude
    )

    $item = Get-Item -LiteralPath $FilePath
    $dir = $item.DirectoryName
    $name = $item.Name
    $relative = ".\$name"
    $latRef = if ($Latitude -ge 0) { 'N' } else { 'S' }
    $lonRef = if ($Longitude -ge 0) { 'E' } else { 'W' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $absLat = [Math]::Abs($Latitude).ToString('0.000000', $culture)
    $absLon = [Math]::Abs($Longitude).ToString('0.000000', $culture)
    $signedLat = $Latitude.ToString('0.000000', $culture)
    $signedLon = $Longitude.ToString('0.000000', $culture)

    Push-Location $dir
    try {
        $arguments = @(
            '-overwrite_original',
            '-all=',
            "-Make=$($Profile.Make)",
            "-Model=$($Profile.Model)",
            "-LensMake=$($Profile.Make)",
            "-LensModel=$($Profile.LensModel)",
            "-GPSLatitude=$absLat",
            "-GPSLatitudeRef=$latRef",
            "-GPSLongitude=$absLon",
            "-GPSLongitudeRef=$lonRef",
            '-GPSMapDatum=WGS-84',
            "-XMP:Make=$($Profile.Make)",
            "-XMP:Model=$($Profile.Model)",
            "-XMP:GPSLatitude=$signedLat",
            "-XMP:GPSLongitude=$signedLon",
            $relative
        )

        $output = Invoke-NativeCommand -Executable $exifToolPath -Arguments $arguments
        return $output
    } finally {
        Pop-Location
    }
}

function Backup-File {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$BackupRoot
    )

    $item = Get-Item -LiteralPath $FilePath
    $safeDirName = ($item.DirectoryName -replace '[:\\/]', '_').Trim('_')
    $targetDir = Join-Path $BackupRoot $safeDirName
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $target = Join-Path $targetDir $item.Name
    if (Test-Path -LiteralPath $target) {
        $base = [IO.Path]::GetFileNameWithoutExtension($item.Name)
        $ext = $item.Extension
        $target = Join-Path $targetDir ("{0}_{1}{2}" -f $base, (Get-Date -Format 'HHmmssfff'), $ext)
    }

    Copy-Item -LiteralPath $FilePath -Destination $target -Force
    return $target
}

function Copy-PhotoWithMetadata {
    param(
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [double]$Latitude,
        [Parameter(Mandatory)] [double]$Longitude
    )

    $outputDirectory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    Copy-Item -LiteralPath $InputPath -Destination $OutputPath -Force
    [void](Invoke-ExifToolForPhoto -FilePath $OutputPath -Profile $Profile -Latitude $Latitude -Longitude $Longitude)
    return $OutputPath
}

function Get-VideoInfo {
    param([Parameter(Mandatory)] [string]$FilePath)

    $jsonText = Invoke-NativeCommand -Executable $ffprobePath -Arguments @(
        '-v', 'error',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        '--', $FilePath
    )
    $json = $jsonText | ConvertFrom-Json
    $video = $json.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $audio = $json.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

    if (-not $video) {
        throw "No video stream found: $FilePath"
    }
    if (-not $json.format -or $null -eq $json.format.duration) {
        throw "Video duration is unavailable: $FilePath"
    }

    return [pscustomobject]@{
        Width = [int]$video.width
        Height = [int]$video.height
        Duration = [double]$json.format.duration
        HasAudio = [bool]$audio
    }
}

function Get-UniqueOutputPath {
    param(
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$OutputDirectory,
        [bool]$UseNeutralName = $true
    )

    if ($UseNeutralName) {
        do {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $shortId = [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
            $candidate = Join-Path $OutputDirectory ("VID_{0}_{1}.mp4" -f $stamp, $shortId)
        } while (Test-Path -LiteralPath $candidate)
    } else {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
        $candidate = Join-Path $OutputDirectory ($baseName + '_clean.mp4')
        $counter = 2
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $OutputDirectory ("{0}_clean_{1}.mp4" -f $baseName, $counter)
            $counter++
        }
    }
    return $candidate
}

function Get-UniquePhotoOutputPath {
    param(
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$OutputDirectory,
        [bool]$UseNeutralName = $true
    )

    $extension = [IO.Path]::GetExtension($InputPath)
    if ($UseNeutralName) {
        do {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $shortId = [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
            $candidate = Join-Path $OutputDirectory ("IMG_{0}_{1}{2}" -f $stamp, $shortId, $extension)
        } while (Test-Path -LiteralPath $candidate)
    } else {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
        $candidate = Join-Path $OutputDirectory ($baseName + '_clean' + $extension)
        $counter = 2
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $OutputDirectory ("{0}_clean_{1}{2}" -f $baseName, $counter, $extension)
            $counter++
        }
    }
    return $candidate
}

function Export-CleanVideo {
    param(
        [Parameter(Mandatory)] [string]$InputPath,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [int]$Crf,
        [Parameter(Mandatory)] [psobject]$Profile,
        [Parameter(Mandatory)] [double]$Latitude,
        [Parameter(Mandatory)] [double]$Longitude,
        [ValidateSet('Compatible', 'Remux')]
        [string]$Mode = 'Compatible'
    )

    $sourceInfo = Get-VideoInfo -FilePath $InputPath
    $qtGps = Convert-ToQuickTimeGps -Latitude $Latitude -Longitude $Longitude
    if ($Mode -eq 'Remux') {
        $ffmpegArguments = @(
            '-hide_banner',
            '-nostdin',
            '-y',
            '-i', $InputPath,
            '-map', '0:v:0',
            '-map', '0:a?',
            '-map_metadata', '-1',
            '-map_chapters', '-1',
            '-c:v', 'copy',
            '-c:a', 'copy',
            '-movflags', '+faststart',
            '-metadata', 'title=',
            '-metadata', 'comment=',
            '-metadata', 'artist=',
            '-metadata', 'copyright=',
            '-metadata', 'encoder=',
            '-metadata:s:v:0', 'encoder=',
            '-metadata:s:a:0', 'encoder=',
            $OutputPath
        )
    } else {
        $ffmpegArguments = @(
            '-hide_banner',
            '-nostdin',
            '-y',
            '-i', $InputPath,
            '-map', '0:v:0',
            '-map', '0:a?',
            '-map_metadata', '-1',
            '-map_chapters', '-1',
            '-c:v', 'libx264',
            '-preset', 'medium',
            '-crf', $Crf.ToString([Globalization.CultureInfo]::InvariantCulture),
            '-pix_fmt', 'yuv420p',
            '-c:a', 'aac',
            '-b:a', '192k',
            '-ar', '48000',
            '-movflags', '+faststart',
            '-metadata', 'title=',
            '-metadata', 'comment=',
            '-metadata', 'artist=',
            '-metadata', 'copyright=',
            '-metadata', 'encoder=',
            '-metadata:s:v:0', 'encoder=',
            '-metadata:s:a:0', 'encoder=',
            $OutputPath
        )
    }

    [void](Invoke-NativeCommand -Executable $ffmpegPath -Arguments $ffmpegArguments)
    [void](Invoke-NativeCommand -Executable $exifToolPath -Arguments @(
        '-overwrite_original',
        '-all=',
        "-Keys:Make=$($Profile.Make)",
        "-Keys:Model=$($Profile.Model)",
        "-LensMake=$($Profile.Make)",
        "-LensModel=$($Profile.LensModel)",
        "-Keys:GPSCoordinates=$qtGps",
        "-QuickTime:Make=$($Profile.Make)",
        "-QuickTime:Model=$($Profile.Model)",
        "-GPSCoordinates=$qtGps",
        $OutputPath
    ))

    $outputInfo = Get-VideoInfo -FilePath $OutputPath
    if ($sourceInfo.Width -ne $outputInfo.Width -or $sourceInfo.Height -ne $outputInfo.Height) {
        throw "Resolution check failed. Source: $($sourceInfo.Width)x$($sourceInfo.Height); output: $($outputInfo.Width)x$($outputInfo.Height)."
    }

    $durationDifference = [Math]::Abs($sourceInfo.Duration - $outputInfo.Duration)
    if ($durationDifference -gt 0.25) {
        throw "Duration check failed. Difference: $([Math]::Round($durationDifference, 3)) sec."
    }

    if ($sourceInfo.HasAudio -ne $outputInfo.HasAudio) {
        throw 'Audio stream check failed.'
    }

    $sourceHash = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
    $outputHash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    if ($sourceHash -eq $outputHash) {
        throw 'Hash check failed: output is byte-identical to source.'
    }

    $metadataJson = Invoke-NativeCommand -Executable $ffprobePath -Arguments @(
        '-v', 'error',
        '-print_format', 'json',
        '-show_entries', 'format_tags:stream_tags',
        '--', $OutputPath
    )
    $metadata = $metadataJson | ConvertFrom-Json
    $metadataText = $metadata | ConvertTo-Json -Depth 8 -Compress
    $blockedMarkers = @(
        'comfyui', 'minimax', 'ref2va', 'openai', 'seedance', 'runway',
        'generated by', 'ai-generated'
    )
    foreach ($marker in $blockedMarkers) {
        if ($metadataText -match [regex]::Escape($marker)) {
            throw "Metadata verification failed: found marker '$marker'."
        }
    }

    $deviceReadbackJson = Invoke-NativeCommand -Executable $exifToolPath -Arguments @(
        '-j',
        '-a',
        '-G1',
        '-s',
        '-n',
        '-Make',
        '-Model',
        '-LensMake',
        '-LensModel',
        '-GPSCoordinates',
        '-Keys:Make',
        '-Keys:Model',
        '-Keys:GPSCoordinates',
        '-QuickTime:Make',
        '-QuickTime:Model',
        $OutputPath
    )

    $deviceReadback = $deviceReadbackJson | ConvertFrom-Json
    $modelFound = $false
    $lensFound = $false
    $gpsFound = $false
    $gpsNumberPattern = '(?<lat>[+-]?\d+(?:\.\d+)?)\s+(?<lon>[+-]?\d+(?:\.\d+)?)'
    foreach ($entry in @($deviceReadback)) {
        foreach ($property in $entry.PSObject.Properties) {
            $propertyName = [string]$property.Name
            $propertyValue = [string]$property.Value
            if ($propertyName -match '(?i)(^|:)Model$' -and $propertyValue -eq [string]$Profile.Model) {
                $modelFound = $true
            }
            if ($propertyName -match '(?i)(^|:)LensModel$' -and $propertyValue -eq [string]$Profile.LensModel) {
                $lensFound = $true
            }
            if ($propertyName -match '(?i)GPSCoordinates$') {
                $gpsMatch = [regex]::Match($propertyValue, $gpsNumberPattern)
                if ($gpsMatch.Success) {
                    $readbackLatitude = [double]::Parse($gpsMatch.Groups['lat'].Value, [Globalization.CultureInfo]::InvariantCulture)
                    $readbackLongitude = [double]::Parse($gpsMatch.Groups['lon'].Value, [Globalization.CultureInfo]::InvariantCulture)
                    if ([Math]::Abs($readbackLatitude - $Latitude) -le 0.0001 -and [Math]::Abs($readbackLongitude - $Longitude) -le 0.0001) {
                        $gpsFound = $true
                    }
                }
            }
        }
    }

    if (-not $modelFound) {
        throw "Device metadata verification failed: model '$($Profile.Model)' was not found."
    }
    if (-not $lensFound) {
        throw "Lens metadata verification failed: '$($Profile.LensModel)' was not found."
    }
    if (-not $gpsFound) {
        throw "GPS metadata verification failed: coordinates '$Latitude, $Longitude' were not found."
    }

    return [pscustomobject]@{
        OutputPath = $OutputPath
        OutputHash = $outputHash
        Duration = $outputInfo.Duration
        Width = $outputInfo.Width
        Height = $outputInfo.Height
        HasAudio = $outputInfo.HasAudio
        Device = $Profile.Display
        GpsCoordinates = $qtGps
        Mode = $Mode
    }
}

$files = New-Object System.Collections.Generic.List[string]
$script:cancelRequested = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Media Clean Export'
$form.Size = New-Object System.Drawing.Size(940, 1000)
$form.MinimumSize = New-Object System.Drawing.Size(940, 1000)
$form.MaximumSize = New-Object System.Drawing.Size(940, 1000)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.AutoScroll = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.StartPosition = 'CenterScreen'
$form.AllowDrop = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Media Clean Export'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(20, 42, 74)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(16, 14)
$form.Controls.Add($title)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'Профиль, объектив и GPS применяются к фото и видео. Безопасный режим сохраняет оригиналы.'
$description.AutoSize = $true
$description.ForeColor = [System.Drawing.Color]::FromArgb(80, 94, 112)
$description.Location = New-Object System.Drawing.Point(18, 44)
$form.Controls.Add($description)

$dropPanel = New-Object System.Windows.Forms.Panel
$dropPanel.BorderStyle = 'FixedSingle'
$dropPanel.AllowDrop = $true
$dropPanel.Location = New-Object System.Drawing.Point(16, 72)
$dropPanel.Size = New-Object System.Drawing.Size(892, 78)
$dropPanel.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($dropPanel)

$dropLabel = New-Object System.Windows.Forms.Label
$dropLabel.Text = 'Перетащите фото/видео или папку сюда'
$dropLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12)
$dropLabel.AutoSize = $true
$dropLabel.Location = New-Object System.Drawing.Point(310, 26)
$dropPanel.Controls.Add($dropLabel)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(16, 162)
$list.Size = New-Object System.Drawing.Size(892, 158)
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $true
$list.HideSelection = $false
$list.MultiSelect = $false
$list.HideSelection = $false
[void]$list.Columns.Add('Файл', 300)
[void]$list.Columns.Add('Тип', 72)
[void]$list.Columns.Add('Статус', 140)
[void]$list.Columns.Add('Результат / ошибка', 360)
$list.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($list)

$addButton = New-Object MediaCleanExport.ThemedButton
$addButton.Text = 'Добавить файлы'
$addButton.Location = New-Object System.Drawing.Point(16, 332)
$addButton.Size = New-Object System.Drawing.Size(132, 32)
$form.Controls.Add($addButton)

$folderButton = New-Object MediaCleanExport.ThemedButton
$folderButton.Text = 'Добавить папку'
$folderButton.Location = New-Object System.Drawing.Point(158, 332)
$folderButton.Size = New-Object System.Drawing.Size(132, 32)
$form.Controls.Add($folderButton)

$clearButton = New-Object MediaCleanExport.ThemedButton
$clearButton.Text = 'Очистить список'
$clearButton.Location = New-Object System.Drawing.Point(300, 332)
$clearButton.Size = New-Object System.Drawing.Size(132, 32)
$form.Controls.Add($clearButton)

$previewButton = New-Object MediaCleanExport.ThemedButton
$previewButton.Text = 'Метаданные'
$previewButton.Location = New-Object System.Drawing.Point(442, 332)
$previewButton.Size = New-Object System.Drawing.Size(150, 32)
$form.Controls.Add($previewButton)

$openOutputButton = New-Object MediaCleanExport.ThemedButton
$openOutputButton.Text = 'Открыть папку'
$openOutputButton.Location = New-Object System.Drawing.Point(602, 332)
$openOutputButton.Size = New-Object System.Drawing.Size(150, 32)
$form.Controls.Add($openOutputButton)

foreach ($button in @($addButton, $folderButton, $clearButton, $previewButton, $openOutputButton)) {
    $button.FlatStyle = 'Flat'
    $button.BackColor = [System.Drawing.Color]::White
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(190, 200, 214)
}

$deviceGroup = New-Object System.Windows.Forms.GroupBox
$deviceGroup.Text = 'Профиль устройства для фото и видео'
$deviceGroup.Location = New-Object System.Drawing.Point(16, 378)
$deviceGroup.Size = New-Object System.Drawing.Size(892, 196)
$deviceGroup.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($deviceGroup)

$deviceLabel = New-Object System.Windows.Forms.Label
$deviceLabel.Text = 'Устройство'
$deviceLabel.AutoSize = $true
$deviceLabel.Location = New-Object System.Drawing.Point(14, 29)
$deviceGroup.Controls.Add($deviceLabel)

$deviceBox = New-Object System.Windows.Forms.ComboBox
$deviceBox.DropDownStyle = 'DropDownList'
$deviceBox.Location = New-Object System.Drawing.Point(104, 25)
$deviceBox.Size = New-Object System.Drawing.Size(390, 26)
foreach ($profile in $script:allDeviceProfiles) {
    [void]$deviceBox.Items.Add($profile.Display)
}
$deviceGroup.Controls.Add($deviceBox)

$profileSearchLabel = New-Object System.Windows.Forms.Label
$profileSearchLabel.Text = 'Поиск'
$profileSearchLabel.AutoSize = $true
$profileSearchLabel.Location = New-Object System.Drawing.Point(510, 30)
$deviceGroup.Controls.Add($profileSearchLabel)

$profileSearchBox = New-Object System.Windows.Forms.TextBox
$profileSearchBox.Location = New-Object System.Drawing.Point(558, 25)
$profileSearchBox.Size = New-Object System.Drawing.Size(150, 24)
$deviceGroup.Controls.Add($profileSearchBox)

$favoriteOnlyCheck = New-Object System.Windows.Forms.CheckBox
$favoriteOnlyCheck.Text = 'Только ★'
$favoriteOnlyCheck.AutoSize = $true
$favoriteOnlyCheck.Location = New-Object System.Drawing.Point(720, 29)
$deviceGroup.Controls.Add($favoriteOnlyCheck)

$deviceStatus = New-Object System.Windows.Forms.Label
$deviceStatus.Text = 'Включён всегда; применяется к фото и видео.'
$deviceStatus.AutoSize = $true
$deviceStatus.Location = New-Object System.Drawing.Point(192, 158)
$deviceStatus.ForeColor = [System.Drawing.Color]::FromArgb(41, 125, 72)
$deviceGroup.Controls.Add($deviceStatus)

$favoriteToggleButton = New-Object MediaCleanExport.ThemedButton
$favoriteToggleButton.Text = '☆ В избранное'
$favoriteToggleButton.Location = New-Object System.Drawing.Point(14, 153)
$favoriteToggleButton.Size = New-Object System.Drawing.Size(166, 30)
$favoriteToggleButton.FlatStyle = 'Flat'
$favoriteToggleButton.BackColor = [System.Drawing.Color]::White
$favoriteToggleButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(190, 200, 214)
$deviceGroup.Controls.Add($favoriteToggleButton)

$makeLabel = New-Object System.Windows.Forms.Label
$makeLabel.Text = 'Марка'
$makeLabel.AutoSize = $true
$makeLabel.Location = New-Object System.Drawing.Point(14, 70)
$deviceGroup.Controls.Add($makeLabel)

$makeBox = New-Object System.Windows.Forms.TextBox
$makeBox.Location = New-Object System.Drawing.Point(64, 66)
$makeBox.Size = New-Object System.Drawing.Size(142, 24)
$makeBox.ReadOnly = $true
$deviceGroup.Controls.Add($makeBox)

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = 'Модель'
$modelLabel.AutoSize = $true
$modelLabel.Location = New-Object System.Drawing.Point(222, 70)
$deviceGroup.Controls.Add($modelLabel)

$modelBox = New-Object System.Windows.Forms.TextBox
$modelBox.Location = New-Object System.Drawing.Point(280, 66)
$modelBox.Size = New-Object System.Drawing.Size(240, 24)
$modelBox.ReadOnly = $true
$deviceGroup.Controls.Add($modelBox)

$lensLabel = New-Object System.Windows.Forms.Label
$lensLabel.Text = 'Объектив'
$lensLabel.AutoSize = $true
$lensLabel.Location = New-Object System.Drawing.Point(538, 70)
$deviceGroup.Controls.Add($lensLabel)

$lensBox = New-Object System.Windows.Forms.ComboBox
$lensBox.DropDownStyle = 'DropDownList'
$lensBox.Location = New-Object System.Drawing.Point(604, 66)
$lensBox.Size = New-Object System.Drawing.Size(270, 24)
$deviceGroup.Controls.Add($lensBox)

$latLabel = New-Object System.Windows.Forms.Label
$latLabel.Text = 'Широта'
$latLabel.AutoSize = $true
$latLabel.Location = New-Object System.Drawing.Point(14, 112)
$deviceGroup.Controls.Add($latLabel)

$latBox = New-Object System.Windows.Forms.TextBox
$latBox.Location = New-Object System.Drawing.Point(74, 108)
$latBox.Size = New-Object System.Drawing.Size(150, 24)
$latBox.Text = $settings.LastLatitude
$deviceGroup.Controls.Add($latBox)

$lonLabel = New-Object System.Windows.Forms.Label
$lonLabel.Text = 'Долгота'
$lonLabel.AutoSize = $true
$lonLabel.Location = New-Object System.Drawing.Point(246, 112)
$deviceGroup.Controls.Add($lonLabel)

$lonBox = New-Object System.Windows.Forms.TextBox
$lonBox.Location = New-Object System.Drawing.Point(316, 108)
$lonBox.Size = New-Object System.Drawing.Size(150, 24)
$lonBox.Text = $settings.LastLongitude
$deviceGroup.Controls.Add($lonBox)

$backupCheck = New-Object System.Windows.Forms.CheckBox
$backupCheck.Text = 'Бэкап при изменении оригинала'
$backupCheck.Checked = $settings.BackupEnabled
$backupCheck.AutoSize = $true
$backupCheck.Location = New-Object System.Drawing.Point(500, 112)
$deviceGroup.Controls.Add($backupCheck)

$videoGroup = New-Object System.Windows.Forms.GroupBox
$videoGroup.Text = 'Настройки видео'
$videoGroup.Location = New-Object System.Drawing.Point(16, 588)
$videoGroup.Size = New-Object System.Drawing.Size(892, 160)
$videoGroup.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($videoGroup)

$qualityLabel = New-Object System.Windows.Forms.Label
$qualityLabel.Text = 'Качество видео'
$qualityLabel.AutoSize = $true
$qualityLabel.Location = New-Object System.Drawing.Point(14, 30)
$videoGroup.Controls.Add($qualityLabel)

$qualityBox = New-Object System.Windows.Forms.ComboBox
$qualityBox.DropDownStyle = 'DropDownList'
$qualityBox.Location = New-Object System.Drawing.Point(120, 26)
$qualityBox.Size = New-Object System.Drawing.Size(180, 26)
[void]$qualityBox.Items.Add('Высокое (CRF 18)')
[void]$qualityBox.Items.Add('Баланс (CRF 20)')
[void]$qualityBox.Items.Add('Меньший файл (CRF 23)')
$qualityIndex = switch ($settings.LastCrf) { 20 { 1 } 23 { 2 } default { 0 } }
$qualityBox.SelectedIndex = $qualityIndex
$videoGroup.Controls.Add($qualityBox)

$neutralNameCheck = New-Object System.Windows.Forms.CheckBox
$neutralNameCheck.Text = 'Нейтральные имена результатов'
$neutralNameCheck.Checked = $settings.NeutralNames
$neutralNameCheck.AutoSize = $true
$neutralNameCheck.Location = New-Object System.Drawing.Point(320, 30)
$videoGroup.Controls.Add($neutralNameCheck)

$videoModeLabel = New-Object System.Windows.Forms.Label
$videoModeLabel.Text = 'Режим видео'
$videoModeLabel.AutoSize = $true
$videoModeLabel.Location = New-Object System.Drawing.Point(510, 30)
$videoGroup.Controls.Add($videoModeLabel)

$videoModeBox = New-Object System.Windows.Forms.ComboBox
$videoModeBox.DropDownStyle = 'DropDownList'
$videoModeBox.Location = New-Object System.Drawing.Point(594, 26)
$videoModeBox.Size = New-Object System.Drawing.Size(285, 26)
[void]$videoModeBox.Items.Add('Совместимый экспорт (H.264/AAC)')
[void]$videoModeBox.Items.Add('Без перекодирования (remux)')
$videoModeBox.SelectedIndex = if ($settings.VideoMode -eq 'Remux') { 1 } else { 0 }
$videoGroup.Controls.Add($videoModeBox)

$keepOriginalCheck = New-Object System.Windows.Forms.CheckBox
$keepOriginalCheck.Text = 'Сохранить оригиналы и создать копии (фото + видео)'
$keepOriginalCheck.Checked = $settings.KeepOriginals
$keepOriginalCheck.AutoSize = $true
$keepOriginalCheck.Location = New-Object System.Drawing.Point(14, 72)
$videoGroup.Controls.Add($keepOriginalCheck)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = 'Папка результата'
$outputLabel.AutoSize = $true
$outputLabel.Location = New-Object System.Drawing.Point(275, 76)
$videoGroup.Controls.Add($outputLabel)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(385, 70)
$outputBox.Size = New-Object System.Drawing.Size(405, 24)
if ($settings.LastOutputDirectory -and (Test-Path -LiteralPath $settings.LastOutputDirectory -PathType Container)) {
$outputBox.Text = $settings.LastOutputDirectory
}
$videoGroup.Controls.Add($outputBox)

$outputButton = New-Object MediaCleanExport.ThemedButton
$outputButton.Text = 'Выбрать...'
$outputButton.Location = New-Object System.Drawing.Point(800, 66)
$outputButton.Size = New-Object System.Drawing.Size(88, 32)
$videoGroup.Controls.Add($outputButton)
$outputButton.FlatStyle = 'Flat'
$outputButton.BackColor = [System.Drawing.Color]::White
$outputButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(190, 200, 214)

$processButton = New-Object MediaCleanExport.ThemedButton
$processButton.Text = 'Начать обработку'
$processButton.Location = New-Object System.Drawing.Point(16, 762)
$processButton.Size = New-Object System.Drawing.Size(220, 42)
$processButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$processButton.ForeColor = [System.Drawing.Color]::White
$processButton.FlatStyle = 'Flat'
$processButton.FlatAppearance.BorderSize = 0
$form.Controls.Add($processButton)

$retryRunButton = New-Object MediaCleanExport.ThemedButton
$retryRunButton.Text = 'Повторить ошибки'
$retryRunButton.Location = New-Object System.Drawing.Point(246, 762)
$retryRunButton.Size = New-Object System.Drawing.Size(150, 42)
$form.Controls.Add($retryRunButton)

$cancelButton = New-Object MediaCleanExport.ThemedButton
$cancelButton.Text = 'Отменить'
$cancelButton.Location = New-Object System.Drawing.Point(406, 762)
$cancelButton.Size = New-Object System.Drawing.Size(120, 42)
$cancelButton.Enabled = $false
$form.Controls.Add($cancelButton)

$toolStatus = New-Object System.Windows.Forms.Label
$toolStatus.Text = if ($ffmpegPath -and $ffprobePath -and $exifToolPath) { 'Инструменты готовы: FFmpeg + FFprobe + ExifTool' } else { 'Не найден FFmpeg, FFprobe или ExifTool' }
$toolStatus.AutoSize = $true
$toolStatus.Location = New-Object System.Drawing.Point(548, 778)
$toolStatus.ForeColor = if ($ffmpegPath -and $ffprobePath -and $exifToolPath) { [System.Drawing.Color]::FromArgb(41, 125, 72) } else { [System.Drawing.Color]::FromArgb(176, 48, 48) }
$form.Controls.Add($toolStatus)

$progress = New-Object MediaCleanExport.ThemedProgressBar
$progress.Location = New-Object System.Drawing.Point(16, 816)
$progress.Size = New-Object System.Drawing.Size(892, 20)
$form.Controls.Add($progress)

$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(16, 846)
$log.Size = New-Object System.Drawing.Size(892, 110)
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$form.Controls.Add($log)

function Add-Log {
    param([string]$Text)
    $log.AppendText(("{0}  {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $Text))
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-LensOptions {
    param([Parameter(Mandatory)] [psobject]$Profile)

    $options = New-Object System.Collections.Generic.List[string]
    if ($Profile.LensModel) {
        $options.Add([string]$Profile.LensModel)
    }

    $model = [string]$Profile.Model
    $options.Add("$model rear main wide camera")
    $options.Add("$model rear ultra-wide camera")

    if ($model -match '(?i)pro|ultra|fold|open|xperia 1|pura|mate') {
        $options.Add("$model rear telephoto camera")
        $options.Add("$model rear portrait telephoto camera")
    }

    if (($Profile.Make -eq 'Samsung' -and $model -match '(?i)A[0-9]') -or $Profile.Make -in @('Xiaomi', 'Motorola')) {
        $options.Add("$model rear macro camera")
    }

    $options.Add("$model front camera")
    return @($options | Select-Object -Unique)
}

function Update-LensOptions {
    param([Parameter(Mandatory)] [psobject]$Profile)

    $lensBox.Items.Clear()
    foreach ($lensOption in @(Get-LensOptions -Profile $Profile)) {
        [void]$lensBox.Items.Add($lensOption)
    }

    if ($Profile.Id -eq 'custom') {
        $lensBox.DropDownStyle = 'DropDown'
        $lensBox.BackColor = [System.Drawing.Color]::White
        $lensValue = $settings.LastCustomLensModel
    } else {
        $lensBox.DropDownStyle = 'DropDownList'
        $lensBox.BackColor = [System.Drawing.Color]::FromArgb(242, 244, 247)
        $lensValue = $settings.LastLensModel
        if (-not $lensValue -or @($lensBox.Items) -notcontains $lensValue) {
            $lensValue = [string]$Profile.LensModel
        }
    }

    if ($lensValue) {
        $lensBox.Text = $lensValue
    } elseif ($lensBox.Items.Count -gt 0) {
        $lensBox.SelectedIndex = 0
    }
}

function Get-CurrentDeviceProfile {
    if ($deviceBox.SelectedIndex -lt 0) {
        return $null
    }

    $profiles = @($script:visibleDeviceProfiles)
    if ($deviceBox.SelectedIndex -ge $profiles.Count) {
        return $null
    }

    return $profiles[$deviceBox.SelectedIndex]
}

function Test-ProfileFavorite {
    param([Parameter(Mandatory)] [psobject]$Profile)

    return @($settings.FavoriteDeviceIds) -contains [string]$Profile.Id
}

function Update-FavoriteButton {
    $selected = Get-CurrentDeviceProfile
    if (-not $selected) {
        $favoriteToggleButton.Text = '☆ В избранное'
        return
    }

    if (Test-ProfileFavorite -Profile $selected) {
        $favoriteToggleButton.Text = '★ Убрать из избранного'
    } else {
        $favoriteToggleButton.Text = '☆ В избранное'
    }
}

function Refresh-DeviceProfileList {
    $selected = Get-CurrentDeviceProfile
    $selectedId = if ($selected) { [string]$selected.Id } else { [string]$settings.LastDeviceId }
    $searchText = $profileSearchBox.Text.Trim()
    $favoriteOnly = $favoriteOnlyCheck.Checked

    $filtered = @($script:allDeviceProfiles | Where-Object {
        $searchMatches = (-not $searchText) -or
            ([string]$_.Display -like "*$searchText*") -or
            ([string]$_.Make -like "*$searchText*") -or
            ([string]$_.Model -like "*$searchText*")
        $favoriteMatches = (-not $favoriteOnly) -or (Test-ProfileFavorite -Profile $_)
        $searchMatches -and $favoriteMatches
    } | Sort-Object GroupOrder, Display)

    $script:visibleDeviceProfiles = $filtered
    $deviceBox.BeginUpdate()
    try {
        $deviceBox.Items.Clear()
        foreach ($profile in $script:visibleDeviceProfiles) {
            [void]$deviceBox.Items.Add($profile.Display)
        }

        $targetIndex = -1
        for ($i = 0; $i -lt $script:visibleDeviceProfiles.Count; $i++) {
            if ([string]$script:visibleDeviceProfiles[$i].Id -eq $selectedId) {
                $targetIndex = $i
                break
            }
        }
        if ($targetIndex -lt 0 -and $deviceBox.Items.Count -gt 0) {
            $targetIndex = 0
        }
        $deviceBox.SelectedIndex = $targetIndex
    } finally {
        $deviceBox.EndUpdate()
    }

    Update-FavoriteButton
}

function Update-ProfileFields {
    if ($deviceBox.SelectedIndex -lt 0) {
        return
    }

    $selected = Get-CurrentDeviceProfile
    if (-not $selected) {
        return
    }
    if ($selected.Id -eq 'custom') {
        $makeBox.ReadOnly = $false
        $modelBox.ReadOnly = $false
        $makeBox.BackColor = [System.Drawing.Color]::White
        $modelBox.BackColor = [System.Drawing.Color]::White
        $makeBox.Text = $settings.LastCustomMake
        $modelBox.Text = $settings.LastCustomModel
        Update-LensOptions -Profile $selected
        $deviceStatus.Text = 'Введите свои значения; они сохранятся.'
        $deviceStatus.ForeColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    } else {
        $makeBox.ReadOnly = $true
        $modelBox.ReadOnly = $true
        $makeBox.BackColor = [System.Drawing.Color]::FromArgb(242, 244, 247)
        $modelBox.BackColor = [System.Drawing.Color]::FromArgb(242, 244, 247)
        $makeBox.Text = $selected.Make
        $modelBox.Text = $selected.Model
        Update-LensOptions -Profile $selected
        $deviceStatus.Text = 'Профиль включён; применяется к фото и видео.'
        $deviceStatus.ForeColor = [System.Drawing.Color]::FromArgb(41, 125, 72)
    }
}

function Get-SelectedProfile {
    if ($deviceBox.SelectedIndex -lt 0) {
        throw 'Выберите профиль устройства.'
    }

    $selected = Get-CurrentDeviceProfile
    if (-not $selected) {
        throw 'Выберите профиль устройства.'
    }
    if ($selected.Id -eq 'custom') {
        $make = $makeBox.Text.Trim()
        $model = $modelBox.Text.Trim()
        $lens = $lensBox.Text.Trim()
        if (-not $make -or -not $model -or -not $lens) {
            throw 'Для своего телефона заполните марку, модель и объектив.'
        }
        return [pscustomobject]@{
            Id = 'custom'
            Display = "Свой телефон: $make $model"
            Make = $make
            Model = $model
            LensModel = $lens
        }
    }

    return [pscustomobject]@{
        Id = $selected.Id
        Display = $selected.Display
        Make = $selected.Make
        Model = $selected.Model
        LensModel = $lensBox.Text.Trim()
    }
}

function Save-CurrentSettings {
    $selected = Get-CurrentDeviceProfile
    if ($selected) {
        $settings.LastDeviceId = $selected.Id
        $settings.LastLensModel = $lensBox.Text
    }
    if ($selected -and $selected.Id -eq 'custom') {
        $settings.LastCustomMake = $makeBox.Text
        $settings.LastCustomModel = $modelBox.Text
        $settings.LastCustomLensModel = $lensBox.Text
    }
    $settings.LastLatitude = $latBox.Text
    $settings.LastLongitude = $lonBox.Text
    $settings.LastCrf = @(18, 20, 23)[$qualityBox.SelectedIndex]
    $settings.VideoMode = if ($videoModeBox.SelectedIndex -eq 1) { 'Remux' } else { 'Compatible' }
    $settings.BackupEnabled = $backupCheck.Checked
    $settings.KeepOriginals = $keepOriginalCheck.Checked
    $settings.NeutralNames = $neutralNameCheck.Checked
    $settings.LastOutputDirectory = $outputBox.Text.Trim()
    [void](Save-Settings -Settings $settings)
}

function Add-PathsToList {
    param([string[]]$Paths)

    $newFiles = @(Get-SupportedFiles -Paths $Paths)
    foreach ($file in $newFiles) {
        if (-not $files.Contains($file)) {
            $files.Add($file)
            $item = New-Object System.Windows.Forms.ListViewItem -ArgumentList ([IO.Path]::GetFileName($file))
            [void]$item.SubItems.Add((Get-MediaKind -FilePath $file))
            [void]$item.SubItems.Add('Ожидает')
            [void]$item.SubItems.Add($file)
            $item.Tag = $file
            [void]$list.Items.Add($item)
        }
    }

    if ($files.Count -gt 0 -and -not $outputBox.Text) {
        $firstDirectory = (Get-Item -LiteralPath $files[0]).DirectoryName
        $outputBox.Text = Join-Path $firstDirectory '_media_clean_exports'
    }

    Add-Log "Добавлено: $($newFiles.Count). Всего: $($files.Count)."
}

function Get-FileRow {
    param([Parameter(Mandatory)] [string]$FilePath)

    foreach ($item in $list.Items) {
        if ([string]$item.Tag -eq $FilePath) {
            return $item
        }
    }
    return $null
}

function Set-FileRowStatus {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$Status,
        [string]$Details = ''
    )

    $item = Get-FileRow -FilePath $FilePath
    if ($item) {
        $item.SubItems[2].Text = $Status
        $item.SubItems[3].Text = $Details
    }
}

function Get-ErrorFilePaths {
    $errorPaths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $list.Items) {
        if ([string]$item.SubItems[2].Text -like 'Ошибка*') {
            $errorPaths.Add([string]$item.Tag)
        }
    }
    return @($errorPaths)
}

function Get-MetadataPreviewText {
    param([Parameter(Mandatory)] [string]$FilePath)

    $item = Get-Item -LiteralPath $FilePath
    $kind = Get-MediaKind -FilePath $FilePath
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Файл: $($item.Name)")
    $lines.Add("Тип: $kind")
    $lines.Add("Размер: $([Math]::Round($item.Length / 1KB, 1)) KB")

    if (-not $exifToolPath) {
        throw 'ExifTool не найден.'
    }

    $jsonText = Invoke-NativeCommand -Executable $exifToolPath -Arguments @(
        '-j',
        '-a',
        '-G1',
        '-s',
        '-Make',
        '-Model',
        '-LensMake',
        '-LensModel',
        '-GPSCoordinates',
        '-GPSLatitude',
        '-GPSLongitude',
        '-DateTimeOriginal',
        '-CreateDate',
        '-FileType',
        $FilePath
    )
    $record = $jsonText | ConvertFrom-Json
    $wantedTags = @('Make', 'Model', 'LensMake', 'LensModel', 'GPSCoordinates', 'GPSLatitude', 'GPSLongitude', 'DateTimeOriginal', 'CreateDate', 'FileType')
    $foundTag = $false
    $seenTags = @{}
    foreach ($entry in @($record)) {
        foreach ($property in $entry.PSObject.Properties) {
            $tagName = ([string]$property.Name -split ':')[-1]
            $tagValue = [string]$property.Value
            $tagKey = "${tagName}|${tagValue}"
            if ($wantedTags -contains $tagName -and $tagValue -and -not $seenTags.ContainsKey($tagKey)) {
                $lines.Add("${tagName}: $tagValue")
                $seenTags[$tagKey] = $true
                $foundTag = $true
            }
        }
    }
    if (-not $foundTag) {
        $lines.Add('Выбранные метаданные не найдены.')
    }

    if ($kind -eq 'Video' -and $ffprobePath) {
        $info = Get-VideoInfo -FilePath $FilePath
        $lines.Add("Видео: $($info.Width)x$($info.Height), $([Math]::Round($info.Duration, 2)) сек., аудио: $(if ($info.HasAudio) { 'да' } else { 'нет' })")
    }

    return ($lines -join "`r`n")
}

function Show-MetadataPreview {
    if ($list.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Выберите файл в списке.', 'Предпросмотр метаданных') | Out-Null
        return
    }

    $filePath = [string]$list.SelectedItems[0].Tag
    try {
        $text = Get-MetadataPreviewText -FilePath $filePath
        [System.Windows.Forms.MessageBox]::Show($text, 'Предпросмотр метаданных') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка предпросмотра') | Out-Null
    }
}

$dragEnter = {
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
}

$dragDrop = {
    $paths = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    Add-PathsToList -Paths $paths
}

$form.Add_DragEnter($dragEnter)
$form.Add_DragDrop($dragDrop)
$dropPanel.Add_DragEnter($dragEnter)
$dropPanel.Add_DragDrop($dragDrop)

$addButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = 'Media files|*.jpg;*.jpeg;*.png;*.heic;*.heif;*.tif;*.tiff;*.webp;*.mp4;*.mov;*.m4v|All files|*.*'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-PathsToList -Paths $dialog.FileNames
    }
})

$folderButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-PathsToList -Paths @($dialog.SelectedPath)
    }
})

$clearButton.Add_Click({
    $files.Clear()
    $list.Items.Clear()
    $progress.Value = 0
    Add-Log 'Список очищен.'
})

$previewButton.Add_Click({
    Show-MetadataPreview
})

$openOutputButton.Add_Click({
    if (-not $outputBox.Text.Trim() -or -not (Test-Path -LiteralPath $outputBox.Text.Trim() -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show('Папка результата ещё не создана.', 'Открыть папку') | Out-Null
        return
    }
    Invoke-Item -LiteralPath $outputBox.Text.Trim()
})

$profileSearchBox.Add_TextChanged({
    Refresh-DeviceProfileList
})

$favoriteOnlyCheck.Add_CheckedChanged({
    Refresh-DeviceProfileList
})

$favoriteToggleButton.Add_Click({
    $selected = Get-CurrentDeviceProfile
    if (-not $selected) {
        return
    }

    $favoriteIds = New-Object System.Collections.Generic.List[string]
    foreach ($favoriteId in @($settings.FavoriteDeviceIds)) {
        if ($favoriteId) {
            $favoriteIds.Add([string]$favoriteId)
        }
    }
    if ($favoriteIds.Contains([string]$selected.Id)) {
        [void]$favoriteIds.Remove([string]$selected.Id)
    } else {
        $favoriteIds.Add([string]$selected.Id)
    }
    $settings.FavoriteDeviceIds = @($favoriteIds)
    [void](Save-Settings -Settings $settings)
    Update-FavoriteButton
    if ($favoriteOnlyCheck.Checked) {
        Refresh-DeviceProfileList
    }
})

$deviceBox.Add_SelectedIndexChanged({
    Update-ProfileFields
    Update-FavoriteButton
    Save-CurrentSettings
})

$makeBox.Add_TextChanged({
    $selected = Get-CurrentDeviceProfile
    if ($selected -and $selected.Id -eq 'custom') {
        $settings.LastCustomMake = $makeBox.Text
        [void](Save-Settings -Settings $settings)
    }
})

$modelBox.Add_TextChanged({
    $selected = Get-CurrentDeviceProfile
    if ($selected -and $selected.Id -eq 'custom') {
        $settings.LastCustomModel = $modelBox.Text
        [void](Save-Settings -Settings $settings)
    }
})

$lensBox.Add_TextChanged({
    $selected = Get-CurrentDeviceProfile
    if ($selected) {
        $settings.LastLensModel = $lensBox.Text
        if ($selected.Id -eq 'custom') {
            $settings.LastCustomLensModel = $lensBox.Text
        }
        [void](Save-Settings -Settings $settings)
    }
})

$qualityBox.Add_SelectedIndexChanged({ Save-CurrentSettings })
$videoModeBox.Add_SelectedIndexChanged({ Save-CurrentSettings })
$backupCheck.Add_CheckedChanged({ Save-CurrentSettings })
$keepOriginalCheck.Add_CheckedChanged({ Save-CurrentSettings })
$neutralNameCheck.Add_CheckedChanged({ Save-CurrentSettings })

$outputButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($outputBox.Text -and (Test-Path -LiteralPath $outputBox.Text -PathType Container)) {
        $dialog.SelectedPath = $outputBox.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dialog.SelectedPath
        Save-CurrentSettings
    }
})

function Set-ProcessingState {
    param([Parameter(Mandatory)] [bool]$Busy)

    if ($variantTab) { $variantTab.Enabled = -not $Busy }

    foreach ($control in @(
        $addButton, $folderButton, $clearButton, $previewButton, $openOutputButton,
        $deviceBox, $profileSearchBox, $favoriteOnlyCheck, $favoriteToggleButton,
        $makeBox, $modelBox, $lensBox, $latBox, $lonBox, $backupCheck,
        $qualityBox, $videoModeBox, $keepOriginalCheck, $neutralNameCheck, $outputBox, $outputButton
    )) {
        $control.Enabled = -not $Busy
    }
    $processButton.Enabled = -not $Busy
    $retryRunButton.Enabled = -not $Busy
    $cancelButton.Enabled = $Busy
}

function Invoke-MediaProcessing {
    param([Parameter(Mandatory)] [string[]]$InputFiles)

    $inputFiles = @($InputFiles | Where-Object { $_ })
    if ($inputFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Нет файлов для обработки.', 'Нет файлов') | Out-Null
        return
    }

    try {
        $videoFiles = @($inputFiles | Where-Object { (Get-MediaKind -FilePath $_) -eq 'Video' })
        $photoFiles = @($inputFiles | Where-Object { (Get-MediaKind -FilePath $_) -eq 'Photo' })
        if ($photoFiles.Count -gt 0 -and -not $exifToolPath) {
            throw 'ExifTool не найден. Положите его в tools\exiftool или добавьте в PATH.'
        }
        if ($videoFiles.Count -gt 0 -and (-not $ffmpegPath -or -not $ffprobePath -or -not $exifToolPath)) {
            throw 'Для видео нужны FFmpeg, FFprobe и ExifTool. Положите их в tools или добавьте в PATH.'
        }

        $lat = [double]::Parse($latBox.Text, [Globalization.CultureInfo]::InvariantCulture)
        $lon = [double]::Parse($lonBox.Text, [Globalization.CultureInfo]::InvariantCulture)
        if ([double]::IsNaN($lat) -or [double]::IsNaN($lon) -or $lat -lt -90 -or $lat -gt 90 -or $lon -lt -180 -or $lon -gt 180) {
            throw 'Широта должна быть от -90 до 90, долгота — от -180 до 180.'
        }

        $profile = Get-SelectedProfile
        $keepOriginals = $keepOriginalCheck.Checked
        $videoMode = if ($videoModeBox.SelectedIndex -eq 1) { 'Remux' } else { 'Compatible' }
        $outputDirectory = $null
        if ($videoFiles.Count -gt 0 -or ($keepOriginals -and $photoFiles.Count -gt 0)) {
            if (-not $outputBox.Text.Trim()) {
                throw 'Для режима копий выберите папку результата.'
            }
            $outputDirectory = $outputBox.Text.Trim()
            New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
        }

        if (-not $keepOriginals -and $photoFiles.Count -gt 0) {
            $warning = 'Галочка сохранения оригиналов снята.`nФото будут изменены на месте.'
            if ($backupCheck.Checked) {
                $warning += '`nПеред этим будет создан бэкап.'
            }
            $answer = [System.Windows.Forms.MessageBox]::Show($warning, 'Изменение оригиналов', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                Add-Log 'Обработка отменена пользователем до запуска.'
                return
            }
        }

        if (-not $keepOriginals -and $photoFiles.Count -gt 0 -and $backupCheck.Checked) {
            $firstDir = (Get-Item -LiteralPath $photoFiles[0]).DirectoryName
            $backupRoot = Join-Path $firstDir ('_media_cleaner_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            Add-Log "Бэкап фото: $backupRoot"
        } else {
            $backupRoot = $null
        }

        Save-CurrentSettings
        $script:cancelRequested = $false
        Set-ProcessingState -Busy $true
        $progress.Minimum = 0
        $progress.Maximum = [Math]::Max(1, $inputFiles.Count)
        $progress.Value = 0

        $ok = 0
        $failed = 0
        $cancelled = $false
        $modeText = if ($videoMode -eq 'Remux') { 'без перекодирования' } else { 'совместимый H.264/AAC' }
        $copyText = if ($keepOriginals) { 'оригиналы сохраняются, создаются копии' } else { 'фото изменяются на месте, видео остаются отдельными экспортами' }
        Add-Log "Старт. Файлов: $($inputFiles.Count). Профиль: $($profile.Display). Режим: $copyText. Видео: $modeText."

        foreach ($file in $inputFiles) {
            if ($script:cancelRequested) {
                $cancelled = $true
                Add-Log 'Остановка после завершения текущего файла.'
                break
            }

            Set-FileRowStatus -FilePath $file -Status 'Обработка...' -Details ''
            try {
                if ((Get-MediaKind -FilePath $file) -eq 'Video') {
                    $outputPath = Get-UniqueOutputPath -InputPath $file -OutputDirectory $outputDirectory -UseNeutralName $neutralNameCheck.Checked
                    Add-Log "Видео: $([IO.Path]::GetFileName($file))"
                    $result = Export-CleanVideo -InputPath $file -OutputPath $outputPath -Crf @(18, 20, 23)[$qualityBox.SelectedIndex] -Profile $profile -Latitude $lat -Longitude $lon -Mode $videoMode
                    $ok++
                    $details = "$([IO.Path]::GetFileName($outputPath)) | $($result.Device) | GPS $($result.GpsCoordinates) | $videoMode"
                    Set-FileRowStatus -FilePath $file -Status 'Готово' -Details $details
                    Add-Log "OK: $details | $($result.Width)x$($result.Height) | SHA256 $($result.OutputHash.Substring(0, 12))..."
                } else {
                    Add-Log "Фото: $([IO.Path]::GetFileName($file))"
                    if ($keepOriginals) {
                        $outputPath = Get-UniquePhotoOutputPath -InputPath $file -OutputDirectory $outputDirectory -UseNeutralName $neutralNameCheck.Checked
                        [void](Copy-PhotoWithMetadata -InputPath $file -OutputPath $outputPath -Profile $profile -Latitude $lat -Longitude $lon)
                        $ok++
                        $details = [IO.Path]::GetFileName($outputPath)
                        Set-FileRowStatus -FilePath $file -Status 'Готово' -Details $details
                        Add-Log "OK: $details | оригинал сохранён | $($profile.Display)"
                    } else {
                        if ($backupRoot) {
                            [void](Backup-File -FilePath $file -BackupRoot $backupRoot)
                        }
                        [void](Invoke-ExifToolForPhoto -FilePath $file -Profile $profile -Latitude $lat -Longitude $lon)
                        $ok++
                        Set-FileRowStatus -FilePath $file -Status 'Готово' -Details 'Оригинал изменён'
                        Add-Log "OK: $([IO.Path]::GetFileName($file)) | оригинал изменён | $($profile.Display)"
                    }
                }
            } catch {
                $failed++
                $errorText = $_.Exception.Message
                Set-FileRowStatus -FilePath $file -Status 'Ошибка' -Details $errorText
                Add-Log "ОШИБКА: $([IO.Path]::GetFileName($file)) :: $errorText"
            }
            $progress.Value = [Math]::Min($progress.Maximum, $progress.Value + 1)
            [System.Windows.Forms.Application]::DoEvents()
        }

        $stateText = if ($cancelled) { 'Остановлено' } else { 'Готово' }
        Add-Log "$stateText. Успешно: $ok, ошибок: $failed."
        [System.Windows.Forms.MessageBox]::Show("$stateText.`nУспешно: $ok`nОшибок: $failed", 'Media Clean Export') | Out-Null
    } catch {
        Add-Log "ОШИБКА: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка') | Out-Null
    } finally {
        Set-ProcessingState -Busy $false
        $script:cancelRequested = $false
    }
}

$cancelButton.Add_Click({
    $script:cancelRequested = $true
    $cancelButton.Enabled = $false
    Add-Log 'Запрошена остановка. Текущий файл будет завершён.'
})

$processButton.Add_Click({
    Invoke-MediaProcessing -InputFiles @($files)
})

$retryRunButton.Add_Click({
    $errorFiles = @(Get-ErrorFilePaths)
    if ($errorFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Ошибочных файлов пока нет.', 'Повторить ошибки') | Out-Null
        return
    }
    Invoke-MediaProcessing -InputFiles $errorFiles
})

$defaultDeviceIndex = 0
for ($i = 0; $i -lt $deviceProfiles.Count; $i++) {
    if ($deviceProfiles[$i].Id -eq $settings.LastDeviceId) {
        $defaultDeviceIndex = $i
        break
    }
}
$deviceBox.SelectedIndex = $defaultDeviceIndex
Update-ProfileFields
Update-FavoriteButton

Add-Log "Готово. Выбран профиль: $($deviceProfiles[$defaultDeviceIndex].Display)."
Add-Log 'Готово к работе. Галочка сохранения оригиналов применяется к фото и видео.'
. (Join-Path $scriptRoot 'VariantUI.ps1')
. (Join-Path $scriptRoot 'AppTheme.ps1')
if (-not $NoShow) { [void]$form.ShowDialog() }

