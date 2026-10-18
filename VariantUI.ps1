$modeTabs = New-Object System.Windows.Forms.TabControl
$modeTabs.Dock = 'Fill'
$modeTabs.Padding = New-Object System.Drawing.Point(18, 8)
$metadataTab = New-Object System.Windows.Forms.TabPage
$metadataTab.Text = 'Метаданные и экспорт'
$metadataTab.AutoScroll = $true
$metadataTab.BackColor = $form.BackColor
$existingControls = @($form.Controls)
foreach ($control in $existingControls) { $metadataTab.Controls.Add($control) }
$variantTab = New-Object System.Windows.Forms.TabPage
$variantTab.Text = 'Варианты контента'
$variantTab.AutoScroll = $true
$variantTab.BackColor = $form.BackColor
[void]$modeTabs.TabPages.Add($metadataTab)
[void]$modeTabs.TabPages.Add($variantTab)
$form.Controls.Add($modeTabs)
$form.MaximumSize = New-Object System.Drawing.Size(0, 0)
$form.MinimumSize = New-Object System.Drawing.Size(960, 680)
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.AutoScroll = $false
$initialHeight = [Math]::Max(680, [Math]::Min(940, [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 24))
$form.Size = New-Object System.Drawing.Size(980, $initialHeight)

$script:variantFiles = New-Object 'System.Collections.Generic.List[string]'
$script:variantBusy = $false
$script:variantLastDirectory = ''
$script:variantPreviewPath = ''
$script:variantAutoOpenPreview = $true
$script:variantPowerShell = $null

function New-VariantRow {
    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true
    $row.AutoSizeMode = 'GrowAndShrink'
    $row.Dock = 'Fill'
    $row.WrapContents = $true
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    return $row
}

function New-VariantLabel {
    param([string]$Text)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Margin = New-Object System.Windows.Forms.Padding(0, 8, 10, 6)
    return $label
}

function New-VariantButton {
    param([string]$Text, [int]$Width = 150)
    $button = New-Object MediaCleanExport.ThemedButton
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, 34)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    return $button
}

$variantLayout = New-Object System.Windows.Forms.TableLayoutPanel
$variantLayout.ColumnCount = 1
$variantLayout.RowCount = 12
$variantLayout.AutoSize = $true
$variantLayout.AutoSizeMode = 'GrowAndShrink'
$variantLayout.Dock = 'Top'
$variantLayout.Padding = New-Object System.Windows.Forms.Padding(16)
$variantLayout.AllowDrop = $true
$variantTab.Controls.Add($variantLayout)
$variantTitle = New-VariantLabel 'Из одного исходника — несколько вариантов'
$variantTitle.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$variantTitle.ForeColor = [System.Drawing.Color]::FromArgb(20, 42, 74)
$variantLayout.Controls.Add($variantTitle, 0, 0)
$variantHelp = New-VariantLabel 'Перетащите фото, видео или папку. Меняется изображение; оригиналы всегда сохраняются.'
$variantLayout.Controls.Add($variantHelp, 0, 1)

$variantList = New-Object System.Windows.Forms.ListView
$variantList.View = 'Details'
$variantList.FullRowSelect = $true
$variantList.HideSelection = $false
$variantList.MultiSelect = $true
$variantList.GridLines = $true
$variantList.Dock = 'Fill'
$variantList.Height = 150
$variantList.BackColor = [System.Drawing.Color]::White
$variantList.AllowDrop = $true
[void]$variantList.Columns.Add('Исходный файл', 365)
[void]$variantList.Columns.Add('Тип', 80)
[void]$variantList.Columns.Add('Готово / нужно', 125)
[void]$variantList.Columns.Add('Статус', 285)
$variantLayout.Controls.Add($variantList, 0, 2)
$variantFilesRow = New-VariantRow
$variantAdd = New-VariantButton 'Добавить файлы'
$variantAddFolder = New-VariantButton 'Добавить папку'
$variantClear = New-VariantButton 'Очистить список'
$variantTotal = New-VariantLabel ''
$variantFilesRow.Controls.AddRange(@($variantAdd, $variantAddFolder, $variantClear, $variantTotal))
$variantLayout.Controls.Add($variantFilesRow, 0, 3)

$variantOptionsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$variantOptionsPanel.ColumnCount = 1
$variantOptionsPanel.AutoSize = $true
$variantOptionsPanel.Dock = 'Fill'
$variantOptionsPanel.BackColor = [System.Drawing.Color]::White
$variantOptionsPanel.Padding = New-Object System.Windows.Forms.Padding(12)
$variantOptionsRow = New-VariantRow
$variantCount = New-Object System.Windows.Forms.NumericUpDown
$variantCount.Minimum = 1
$variantCount.Maximum = 1000
$variantCount.Width = 76
$variantCount.Margin = New-Object System.Windows.Forms.Padding(0, 4, 20, 0)
$variantStrength = New-Object System.Windows.Forms.ComboBox
$variantStrength.DropDownStyle = 'DropDownList'
$variantStrength.Width = 145
$variantStrength.Margin = New-Object System.Windows.Forms.Padding(0, 4, 20, 0)
[void]$variantStrength.Items.Add('Бережная')
[void]$variantStrength.Items.Add('Выраженная')
$variantQuality = New-Object System.Windows.Forms.ComboBox
$variantQuality.DropDownStyle = 'DropDownList'
$variantQuality.Width = 140
$variantQuality.Margin = New-Object System.Windows.Forms.Padding(0, 4, 20, 0)
[void]$variantQuality.Items.Add('Высокое')
[void]$variantQuality.Items.Add('Сбалансированное')
[void]$variantQuality.Items.Add('Компактное')
$variantPhotoFormat = New-Object System.Windows.Forms.ComboBox
$variantPhotoFormat.DropDownStyle = 'DropDownList'
$variantPhotoFormat.Width = 70
$variantPhotoFormat.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
[void]$variantPhotoFormat.Items.Add('JPG')
[void]$variantPhotoFormat.Items.Add('PNG')
$variantOptionsRow.Controls.AddRange(@((New-VariantLabel 'N на файл'), $variantCount, (New-VariantLabel 'Обработка'), $variantStrength, (New-VariantLabel 'Качество'), $variantQuality, (New-VariantLabel 'Фото'), $variantPhotoFormat))
$variantOptionsPanel.Controls.Add($variantOptionsRow, 0, 0)
$variantAdvancedToggle = New-VariantButton 'Настроить преобразования ▼' 260
$variantOptionsPanel.Controls.Add($variantAdvancedToggle, 0, 1)
$variantAdvanced = New-VariantRow
$variantAdvanced.Visible = $false
$variantChecks = @{}
foreach ($definition in @(
    @('Crop', 'Кадрирование / зум'), @('Tone', 'Цвет / яркость / контраст'),
    @('Speed', 'Изменять скорость видео'), @('Trim', 'Подрезать начало / конец'),
    @('Mirror', 'Разрешить отражение'), @('StripMetadata', 'Очищать личные метаданные')
)) {
    $check = New-Object System.Windows.Forms.CheckBox
    $check.Text = $definition[1]
    $check.AutoSize = $true
    $check.Margin = New-Object System.Windows.Forms.Padding(0, 8, 20, 8)
    $variantChecks[$definition[0]] = $check
    $variantAdvanced.Controls.Add($check)
}
$variantOptionsPanel.Controls.Add($variantAdvanced, 0, 2)
$variantPresetHelp = New-VariantLabel 'Бережная обработка: лёгкий зум и цветокоррекция. Скорость, подрезка и отражение — только по выбору.'
$variantOptionsPanel.Controls.Add($variantPresetHelp, 0, 3)
$variantLayout.Controls.Add($variantOptionsPanel, 0, 4)

$variantOutputRow = New-Object System.Windows.Forms.TableLayoutPanel
$variantOutputRow.ColumnCount = 3
$variantOutputRow.AutoSize = $true
$variantOutputRow.Dock = 'Fill'
[void]$variantOutputRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
[void]$variantOutputRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$variantOutputRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$variantOutput = New-Object System.Windows.Forms.TextBox
$variantOutput.Dock = 'Fill'
$variantOutput.Margin = New-Object System.Windows.Forms.Padding(0, 6, 12, 6)
$variantChooseOutput = New-VariantButton 'Выбрать папку…' 145
$variantOutputRow.Controls.Add((New-VariantLabel 'Результаты'), 0, 0)
$variantOutputRow.Controls.Add($variantOutput, 1, 0)
$variantOutputRow.Controls.Add($variantChooseOutput, 2, 0)
$variantLayout.Controls.Add($variantOutputRow, 0, 5)
$variantActions = New-VariantRow
$variantRun = New-VariantButton 'Создать варианты' 180
$variantRun.BackColor = [System.Drawing.Color]::FromArgb(32, 91, 171)
$variantRun.ForeColor = [System.Drawing.Color]::White
$variantPreview = New-VariantButton 'Сделать пробу' 150
$variantOpenPreview = New-VariantButton 'Открыть пробу' 140
$variantOpenPreview.Enabled = $false
$variantCancel = New-VariantButton 'Остановить' 120
$variantCancel.Enabled = $false
$variantOpenFolder = New-VariantButton 'Папка результата' 155
$variantOpenFolder.Enabled = $false
$variantActions.Controls.AddRange(@($variantRun, $variantPreview, $variantOpenPreview, $variantCancel, $variantOpenFolder))
$variantLayout.Controls.Add($variantActions, 0, 6)
$variantStatus = New-VariantLabel 'Добавьте исходник. Проба: одно фото или первые 5 секунд выбранного видео.'
$variantLayout.Controls.Add($variantStatus, 0, 7)
$variantProgress = New-Object MediaCleanExport.ThemedProgressBar
$variantProgress.Dock = 'Fill'
$variantProgress.Height = 20
$variantLayout.Controls.Add($variantProgress, 0, 8)
$variantLog = New-Object System.Windows.Forms.TextBox
$variantLog.Multiline = $true
$variantLog.ReadOnly = $true
$variantLog.ScrollBars = 'Vertical'
$variantLog.Height = 110
$variantLog.Dock = 'Fill'
$variantLayout.Controls.Add($variantLog, 0, 9)
$variantNotice = New-VariantLabel 'Проверяются различия в изображении. Решение площадок о сходстве контента может отличаться.'
$variantNotice.ForeColor = [System.Drawing.Color]::FromArgb(80, 94, 112)
$variantLayout.Controls.Add($variantNotice, 0, 10)

function Add-VariantLog {
    param([string]$Text)
    $variantLog.AppendText((Get-Date -Format 'HH:mm:ss') + '  ' + $Text + [Environment]::NewLine)
}

function Get-VariantUserMessage {
    param([string]$Message)
    switch -Wildcard ($Message) {
        'Enable at least one*' { return 'Включите хотя бы одно преобразование изображения или видео.' }
        'Photos require*' { return 'Для фото включите кадрирование, цветокоррекцию или отражение.' }
        'Not enough visual diversity*' { return 'Не хватает различий в выбранных пределах. Уменьшите N или включите дополнительные преобразования.' }
        'Output audio/duration*' { return 'Результат не прошёл проверку звука или длительности. Подробности доступны в отчёте.' }
        default { return $Message }
    }
}

function Get-VariantUiOptions {
    $options = Get-VariantDefaultOptions
    $options.Count = [int]$variantCount.Value
    $options.Strength = if ($variantStrength.SelectedIndex -eq 1) { 'Expressive' } else { 'Gentle' }
    $options.Crf = @(18, 20, 23)[[Math]::Max(0, $variantQuality.SelectedIndex)]
    $options.PhotoFormat = if ($variantPhotoFormat.SelectedIndex -eq 1) { 'Png' } else { 'Jpeg' }
    $options.OutputDirectory = $variantOutput.Text.Trim()
    foreach ($key in $variantChecks.Keys) { $options.$key = $variantChecks[$key].Checked }
    return $options
}

function Save-VariantUiSettings {
    $settings.VariantOptions = Get-VariantUiOptions
    [void](Save-Settings $settings)
    $variantTotal.Text = 'Всего: ' + ($script:variantFiles.Count * [int]$variantCount.Value)
    $variantOpenPreview.Enabled = $false
    $variantPresetHelp.Text = if ($variantStrength.SelectedIndex -eq 1) {
        'Выраженная обработка: более заметное кадрирование и цвет. Дополнительные изменения — по выбору.'
    } else { 'Бережная обработка: лёгкий зум и цветокоррекция. Скорость, подрезка и отражение — только по выбору.' }
}

function Add-VariantInputs {
    param([string[]]$Paths)
    if ($script:variantBusy) { return }
    foreach ($path in @(Get-SupportedFiles $Paths)) {
        if ($script:variantFiles.Contains($path)) { continue }
        $script:variantFiles.Add($path)
        $row = New-Object System.Windows.Forms.ListViewItem([IO.Path]::GetFileName($path))
        $row.Tag = $path
        [void]$row.SubItems.Add($(if ((Get-MediaKind $path) -eq 'Video') { 'Видео' } else { 'Фото' }))
        [void]$row.SubItems.Add('0 / ' + [int]$variantCount.Value)
        [void]$row.SubItems.Add('Ожидает')
        [void]$variantList.Items.Add($row)
    }
    Save-VariantUiSettings
}

function Set-VariantBusy {
    param([bool]$Busy)
    $script:variantBusy = $Busy
    foreach ($control in @($variantAdd, $variantAddFolder, $variantClear, $variantOptionsPanel, $variantChooseOutput, $variantOutput, $variantRun, $variantPreview, $variantList)) { $control.Enabled = -not $Busy }
    $variantCancel.Enabled = $Busy
    $metadataTab.Enabled = -not $Busy
}

function Show-VariantPreview {
    if (-not (Test-Path -LiteralPath $script:variantPreviewPath -PathType Leaf)) { return }
    if ([IO.Path]::GetExtension($script:variantPreviewPath) -eq '.mp4') {
        try { [void][System.Diagnostics.Process]::Start($script:variantPreviewPath) }
        catch { Add-VariantLog ('Не удалось открыть проигрыватель: ' + $_.Exception.Message) }
        return
    }
    $previewWindow = New-Object System.Windows.Forms.Form
    $previewWindow.Text = 'Пробный вариант — ' + [IO.Path]::GetFileName($script:variantPreviewPath)
    $previewWindow.Size = New-Object System.Drawing.Size(760, 700)
    $previewWindow.StartPosition = 'CenterParent'
    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Dock = 'Fill'
    $picture.SizeMode = 'Zoom'
    $picture.BackColor = [System.Drawing.Color]::FromArgb(30, 36, 44)
    $loaded = [System.Drawing.Image]::FromFile($script:variantPreviewPath)
    try { $picture.Image = New-Object System.Drawing.Bitmap($loaded) } finally { $loaded.Dispose() }
    $previewWindow.Controls.Add($picture)
    $previewWindow.Add_FormClosed({ $this.Controls[0].Image.Dispose(); $this.Dispose() })
    $previewWindow.Show($form)
}

function Start-VariantRun {
    param([switch]$Preview)
    if ($script:variantBusy) { return }
    try {
        $options = Get-VariantUiOptions
        Test-VariantOptions $options
        if (-not $script:variantFiles.Count) { throw 'Добавьте хотя бы одно фото или видео.' }
        if (-not $ffmpegPath -or -not $ffprobePath) { throw 'Нужны FFmpeg и FFprobe. Проверьте установку инструментов.' }
        if (-not $options.OutputDirectory) { throw 'Выберите папку для результатов.' }
        [void](New-Item -ItemType Directory -Force -Path $options.OutputDirectory)
        Save-VariantUiSettings
        $inputs = @($script:variantFiles)
        if ($Preview) {
            $inputs = if ($variantList.SelectedItems.Count) { @([string]$variantList.SelectedItems[0].Tag) } else { @($inputs[0]) }
        }
        foreach ($row in $variantList.Items) {
            if ($inputs -contains [string]$row.Tag) {
                $row.SubItems[2].Text = '0 / ' + $(if ($Preview) { 1 } else { $options.Count })
                $row.SubItems[3].Text = 'Ожидает'
            }
        }
        $script:variantState = [hashtable]::Synchronized(@{ CancelRequested = $false; ActiveProcessId = $null })
        $script:variantEvents = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:variantPowerShell = [powershell]::Create()
        [void]$script:variantPowerShell.AddScript({
            param($EnginePath, $Inputs, $Options, $FFmpeg, $FFprobe, $State, $Events, $IsPreview)
            $ErrorActionPreference = 'Stop'
            . $EnginePath
            Invoke-VariantBatch -InputPaths $Inputs -Options $Options -FFmpegPath $FFmpeg -FFprobePath $FFprobe -State $State -Events $Events -Preview:$IsPreview
        }).AddArgument((Join-Path $scriptRoot 'VariantEngine.ps1')).AddArgument($inputs).AddArgument($options).AddArgument($ffmpegPath).AddArgument($ffprobePath).AddArgument($script:variantState).AddArgument($script:variantEvents).AddArgument([bool]$Preview)
        Set-VariantBusy $true
        $script:variantAsync = $script:variantPowerShell.BeginInvoke()
        $variantStatus.Text = 'Подготовка исходников…'
        Add-VariantLog $(if ($Preview) { 'Создание пробного варианта.' } else { 'Начата партия. Каждый вариант создаётся из оригинала.' })
        $variantTimer.Start()
    } catch {
        $message = Get-VariantUserMessage $_.Exception.Message
        Add-VariantLog ('ОШИБКА: ' + $message)
        $variantStatus.Text = $message
        if ($script:variantPowerShell) { $script:variantPowerShell.Dispose(); $script:variantPowerShell = $null }
        Set-VariantBusy $false
    }
}

function Receive-VariantEvents {
    $eventData = $null
    while ($script:variantEvents.TryDequeue([ref]$eventData)) {
        if ($eventData.Type -eq 'Started') {
            $variantProgress.Value = 0
            $variantProgress.Maximum = [int]$eventData.Total
            $script:variantLastDirectory = $eventData.Directory
            $variantOpenFolder.Enabled = $true
        } elseif ($eventData.Type -eq 'Working') {
            $variantStatus.Text = ('Готово {0} из {1} • {2} • вариант {3}, попытка {4}' -f $eventData.Done, $eventData.Total, [IO.Path]::GetFileName($eventData.Source), $eventData.Index, $eventData.Attempt)
        } elseif ($eventData.Type -in @('Done', 'Failed')) {
            $item = $eventData.Item
            $row = @($variantList.Items | Where-Object { $_.Tag -eq $item.Source })[0]
            if ($eventData.Type -eq 'Done') {
                if ($row) { $row.SubItems[2].Text = ([string]$item.Index + $row.SubItems[2].Text.Substring($row.SubItems[2].Text.IndexOf(' / '))); $row.SubItems[3].Text = 'Создан: ' + [IO.Path]::GetFileName($item.Path) }
                $variantProgress.Value = [Math]::Min($variantProgress.Maximum, [int]$eventData.Done)
                Add-VariantLog ('ГОТОВО: ' + [IO.Path]::GetFileName($item.Path))
            } else {
                if ($row) { $row.SubItems[3].Text = 'Не создано: ' + $item.Missing }
                Add-VariantLog ('ОШИБКА: ' + [IO.Path]::GetFileName($item.Source) + ' — ' + (Get-VariantUserMessage $item.Error))
            }
        }
        $eventData = $null
    }
}

$variantTimer = New-Object System.Windows.Forms.Timer
$variantTimer.Interval = 150
$variantTimer.Add_Tick({
    Receive-VariantEvents
    if (-not $script:variantAsync.IsCompleted) { return }
    $variantTimer.Stop()
    try {
        $results = @($script:variantPowerShell.EndInvoke($script:variantAsync))
        if ($script:variantPowerShell.HadErrors) { throw ($script:variantPowerShell.Streams.Error | Out-String) }
        Receive-VariantEvents
        $result = $results[-1]
        $script:variantLastResult = $result
        $variantStatus.Text = ('{0}. Готово {1} из {2}; не создано: {3}.' -f $(if ($result.Cancelled) { 'Остановлено' } elseif ($result.Failed) { 'Партия завершена с ошибками' } else { 'Готово' }), $result.Success, $result.Requested, ($result.Requested - $result.Success))
        Add-VariantLog $variantStatus.Text
        Add-VariantLog ('Отчёт: ' + $result.ManifestPath)
        foreach ($row in $variantList.Items) {
            if ($row.SubItems[3].Text -eq 'Ожидает') { $row.SubItems[3].Text = if ($result.Cancelled) { 'Остановлено' } else { 'Не обработано' } }
        }
        if ($result.PreviewPath) {
            $script:variantPreviewPath = $result.PreviewPath
            $variantOpenPreview.Enabled = $true
            if ($script:variantAutoOpenPreview) { Show-VariantPreview }
        }
    } catch {
        $variantStatus.Text = 'Ошибка обработки. Подробности в журнале.'
        Add-VariantLog ('ОШИБКА: ' + $_.Exception.Message)
    } finally {
        $script:variantPowerShell.Dispose()
        $script:variantPowerShell = $null
        Set-VariantBusy $false
    }
})

$restored = $settings.VariantOptions
$variantCount.Value = [Math]::Max(1, [Math]::Min(1000, [int]$restored.Count))
$variantStrength.SelectedIndex = if ($restored.Strength -eq 'Expressive') { 1 } else { 0 }
$variantQuality.SelectedIndex = [Math]::Max(0, [Array]::IndexOf(@(18, 20, 23), [int]$restored.Crf))
$variantPhotoFormat.SelectedIndex = if ($restored.PhotoFormat -eq 'Png') { 1 } else { 0 }
$variantOutput.Text = [string]$restored.OutputDirectory
foreach ($key in $variantChecks.Keys) { $variantChecks[$key].Checked = [bool]$restored.$key }
$modeTabs.SelectedIndex = if ($settings.LastMode -eq 'Variants') { 1 } else { 0 }

$variantAdd.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = 'Фото и видео|*.jpg;*.jpeg;*.png;*.heic;*.heif;*.tif;*.tiff;*.webp;*.mp4;*.mov;*.m4v'
    try { if ($dialog.ShowDialog() -eq 'OK') { Add-VariantInputs $dialog.FileNames } } finally { $dialog.Dispose() }
})
$variantAddFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try { if ($dialog.ShowDialog() -eq 'OK') { Add-VariantInputs @($dialog.SelectedPath) } } finally { $dialog.Dispose() }
})
$variantClear.Add_Click({ $script:variantFiles.Clear(); $variantList.Items.Clear(); Save-VariantUiSettings })
$variantChooseOutput.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try { if ($dialog.ShowDialog() -eq 'OK') { $variantOutput.Text = $dialog.SelectedPath } } finally { $dialog.Dispose() }
})
$variantAdvancedToggle.Add_Click({
    $variantAdvanced.Visible = -not $variantAdvanced.Visible
    $variantAdvancedToggle.Text = if ($variantAdvanced.Visible) { 'Скрыть преобразования ▲' } else { 'Настроить преобразования ▼' }
})
$variantCount.Add_ValueChanged({ Save-VariantUiSettings })
$variantStrength.Add_SelectedIndexChanged({ Save-VariantUiSettings })
$variantQuality.Add_SelectedIndexChanged({ Save-VariantUiSettings })
$variantPhotoFormat.Add_SelectedIndexChanged({ Save-VariantUiSettings })
$variantOutput.Add_TextChanged({ Save-VariantUiSettings })
foreach ($check in $variantChecks.Values) { $check.Add_CheckedChanged({ Save-VariantUiSettings }) }
$variantRun.Add_Click({ Start-VariantRun })
$variantPreview.Add_Click({ Start-VariantRun -Preview })
$variantOpenPreview.Add_Click({ Show-VariantPreview })
$variantOpenFolder.Add_Click({ if (Test-Path -LiteralPath $script:variantLastDirectory) { [void][System.Diagnostics.Process]::Start($script:variantLastDirectory) } })
$variantCancel.Add_Click({ $script:variantState.CancelRequested = $true; $variantCancel.Enabled = $false; $variantStatus.Text = 'Остановка текущей обработки…' })
$variantDragEnter = { if (-not $script:variantBusy -and $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } }
$variantDragDrop = { Add-VariantInputs @($_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) }
foreach ($dropTarget in @($variantTab, $variantLayout, $variantList)) { $dropTarget.AllowDrop = $true; $dropTarget.Add_DragEnter($variantDragEnter); $dropTarget.Add_DragDrop($variantDragDrop) }
$modeTabs.Add_Selecting({ if (($script:variantBusy -and $_.TabPage -eq $metadataTab) -or ($cancelButton.Enabled -and $_.TabPage -eq $variantTab)) { $_.Cancel = $true } })
$modeTabs.Add_SelectedIndexChanged({ $settings.LastMode = if ($modeTabs.SelectedIndex -eq 1) { 'Variants' } else { 'Metadata' }; [void](Save-Settings $settings) })
$form.Add_FormClosing({
    if ($script:variantBusy) {
        $_.Cancel = $true
        $script:variantState.CancelRequested = $true
        $variantStatus.Text = 'Остановка обработки. После её завершения можно закрыть окно.'
    }
})
$form.Add_FormClosed({ $variantTimer.Dispose() })
$variantTotal.Text = 'Всего: 0'
