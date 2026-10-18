# Common palette and a fixed footer shared by both application modes.
$appFooter = New-Object System.Windows.Forms.Panel
$appFooter.Dock = 'Bottom'
$appFooter.Height = 100
$appFooter.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)
$form.Controls.Add($appFooter)
$themeTitle = New-Object System.Windows.Forms.Label
$themeTitle.Text = 'Оформление'
$themeTitle.AutoSize = $true
$themeTitle.Location = New-Object System.Drawing.Point(18, 10)
$appFooter.Controls.Add($themeTitle)
$themeLightButton = New-VariantButton 'Светлая' 100
$themeLightButton.Location = New-Object System.Drawing.Point(18, 34)
$themeDarkButton = New-VariantButton 'Тёмная' 100
$themeDarkButton.Location = New-Object System.Drawing.Point(128, 34)
$appFooter.Controls.AddRange(@($themeLightButton, $themeDarkButton))
$appCredit = New-Object System.Windows.Forms.LinkLabel
$appCredit.Text = 'Powered by slavytich'
$appCredit.AutoSize = $true
$appCredit.LinkBehavior = 'HoverUnderline'
[void]$appCredit.Links.Add(11, $appCredit.Text.Length - 11, 'https://t.me/slavytich23')
$appCredit.Anchor = 'Bottom,Right'
$appFooter.Controls.Add($appCredit)
$footerNote = New-Object System.Windows.Forms.Label
$footerNote.Text = 'Фото и видео • обработка на вашем компьютере'
$footerNote.AutoSize = $true
$footerNote.Anchor = 'Top,Right'
$appFooter.Controls.Add($footerNote)
$footerLine = New-Object System.Windows.Forms.Panel
$footerLine.Dock = 'Top'
$footerLine.Height = 1
$appFooter.Controls.Add($footerLine)
$tabHeaderFill = New-Object System.Windows.Forms.Panel
$tabHeaderFill.Height = 43
$form.Controls.Add($tabHeaderFill)
$tabHeaderFill.BringToFront()
$form.Add_Layout({
    if ($modeTabs.TabCount -gt 1) {
        $rightEdge = $modeTabs.GetTabRect(1).Right + 2
        $tabHeaderFill.SetBounds(($modeTabs.Left + $rightEdge), $modeTabs.Top, [Math]::Max(0, $modeTabs.Width - $rightEdge), 42)
    }
})
$appFooter.Add_Resize({
    $appCredit.Location = New-Object System.Drawing.Point(($appFooter.ClientSize.Width - $appCredit.Width - 18), 48)
    $footerNote.Location = New-Object System.Drawing.Point(($appFooter.ClientSize.Width - $footerNote.Width - 18), 16)
})
$appCredit.Add_LinkClicked({
    try { [void][System.Diagnostics.Process]::Start('https://t.me/slavytich23') }
    catch { [System.Windows.Forms.MessageBox]::Show('Не удалось открыть Telegram: ' + $_.Exception.Message, 'Telegram') | Out-Null }
})

function Set-AppRoundedRegion {
    param([System.Windows.Forms.Control]$Control)
    if ($Control.Width -lt 12 -or $Control.Height -lt 12) { return }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = 12
    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc(($Control.Width - $diameter), 0, $diameter, $diameter, 270, 90)
    $path.AddArc(($Control.Width - $diameter), ($Control.Height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc(0, ($Control.Height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $oldRegion = $Control.Region
    $Control.Region = New-Object System.Drawing.Region($path)
    if ($oldRegion) { $oldRegion.Dispose() }
    $path.Dispose()
}

function Set-AppTheme {
    param([ValidateSet('Dark', 'Light')][string]$Theme)
    $dark = $Theme -eq 'Dark'
    $script:appPalette = if ($dark) {
        @{
            Background = '#111827'; Surface = '#192335'; Input = '#0E1625'; Text = '#E6ECF6'
            Muted = '#9AAAC2'; Border = '#35435B'; Accent = '#507CF6'; Hover = '#24344D'
        }
    } else {
        @{
            Background = '#F3F6FB'; Surface = '#FFFFFF'; Input = '#FFFFFF'; Text = '#172841'
            Muted = '#566984'; Border = '#CCD6E5'; Accent = '#3266DC'; Hover = '#E8EFFB'
        }
    }
    $palette = @{}
    foreach ($key in $script:appPalette.Keys) { $palette[$key] = [System.Drawing.ColorTranslator]::FromHtml($script:appPalette[$key]) }
    $pending = New-Object 'System.Collections.Generic.Queue[System.Windows.Forms.Control]'
    $pending.Enqueue($form)
    while ($pending.Count) {
        $control = $pending.Dequeue()
        $control.BackColor = $palette.Background
        $control.ForeColor = $palette.Text
        if ($control -is [System.Windows.Forms.Button]) {
            $control.FlatStyle = 'Flat'
            $control.FlatAppearance.BorderSize = 1
            $control.FlatAppearance.BorderColor = $palette.Border
            $control.FlatAppearance.MouseOverBackColor = $palette.Hover
            $control.BackColor = $palette.Surface
            if ($control -is [MediaCleanExport.ThemedButton]) {
                $control.BorderColor = $palette.Border
                $control.HoverColor = $palette.Hover
                $control.DisabledTextColor = $palette.Muted
            }
            if ($control -eq $processButton -or $control -eq $variantRun) {
                $control.BackColor = $palette.Accent
                $control.ForeColor = [System.Drawing.Color]::White
                $control.FlatAppearance.BorderColor = $palette.Accent
                $control.BorderColor = $palette.Accent
            }
            Set-AppRoundedRegion $control
        } elseif ($control -is [System.Windows.Forms.TextBox] -or $control -is [System.Windows.Forms.ListView] -or $control -is [System.Windows.Forms.ComboBox] -or $control -is [System.Windows.Forms.NumericUpDown]) {
            $control.BackColor = $palette.Input
            if ($control -is [System.Windows.Forms.TextBox]) { $control.BorderStyle = 'FixedSingle' }
            if ($control -is [System.Windows.Forms.ComboBox]) { $control.FlatStyle = 'Flat' }
        } elseif ($control -is [System.Windows.Forms.GroupBox] -or $control -eq $variantOptionsPanel -or $control -eq $dropPanel -or $control -eq $appFooter) {
            $control.BackColor = $palette.Surface
        } elseif ($control -is [System.Windows.Forms.Label]) {
            $control.ForeColor = $palette.Muted
        }
        if ($control -is [System.Windows.Forms.CheckBox]) { $control.FlatStyle = 'Flat' }
        if ($control -is [MediaCleanExport.ThemedProgressBar]) {
            $control.TrackColor = $palette.Surface
            $control.FillColor = $palette.Accent
            $control.Invalidate()
        }
        foreach ($child in $control.Controls) { $pending.Enqueue($child) }
    }
    foreach ($heading in @($title, $variantTitle)) { $heading.ForeColor = $palette.Text }
    foreach ($panel in @($deviceGroup, $videoGroup, $variantOptionsPanel, $appFooter, $dropPanel)) {
        foreach ($child in $panel.Controls) {
            if ($child -is [System.Windows.Forms.Label] -or $child -is [System.Windows.Forms.CheckBox] -or $child -is [System.Windows.Forms.FlowLayoutPanel]) { $child.BackColor = $panel.BackColor }
        }
    }
    foreach ($child in $variantOptionsRow.Controls) { if ($child -is [System.Windows.Forms.Label]) { $child.BackColor = $palette.Surface } }
    foreach ($child in $variantAdvanced.Controls) { $child.BackColor = $palette.Surface }
    $appCredit.LinkColor = $palette.Text
    $appCredit.ActiveLinkColor = $palette.Accent
    $appCredit.VisitedLinkColor = $palette.Text
    $appCredit.BackColor = $palette.Surface
    $footerLine.BackColor = $palette.Border
    $selected = if ($dark) { $themeDarkButton } else { $themeLightButton }
    $selected.BackColor = $palette.Hover
    $selected.FlatAppearance.BorderColor = $palette.Accent
    $selected.BorderColor = $palette.Accent
    $selected.ForeColor = $palette.Text
    $selected.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $other = if ($dark) { $themeLightButton } else { $themeDarkButton }
    $other.Font = $form.Font
    $other.ForeColor = $palette.Muted
    $settings.Theme = $Theme
    $modeTabs.Invalidate()
}

foreach ($themedList in @($list, $variantList)) {
    $themedList.OwnerDraw = $true
    $themedList.GridLines = $false
    $themedList.Add_DrawColumnHeader({
        $background = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Surface))
        $_.Graphics.FillRectangle($background, $_.Bounds)
        $background.Dispose()
        $rect = New-Object System.Drawing.Rectangle(($_.Bounds.X + 8), $_.Bounds.Y, ($_.Bounds.Width - 10), $_.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $_.Header.Text, $form.Font, $rect, [System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Muted), [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    })
    $themedList.Add_DrawItem({ })
    $themedList.Add_Resize({
        $usedWidth = 0
        for ($columnIndex = 0; $columnIndex -lt $this.Columns.Count - 1; $columnIndex++) { $usedWidth += $this.Columns[$columnIndex].Width }
        $this.Columns[$this.Columns.Count - 1].Width = [Math]::Max(100, $this.ClientSize.Width - $usedWidth - 2)
    })
    $themedList.Add_DrawSubItem({
        $background = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($(if ($_.Item.Selected) { $script:appPalette.Hover } else { $script:appPalette.Input })))
        $_.Graphics.FillRectangle($background, $_.Bounds)
        $background.Dispose()
        $rect = New-Object System.Drawing.Rectangle(($_.Bounds.X + 8), $_.Bounds.Y, ($_.Bounds.Width - 10), $_.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $_.SubItem.Text, $form.Font, $rect, [System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Text), [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix)
    })
}

foreach ($themedCombo in @($deviceBox, $lensBox, $qualityBox, $videoModeBox, $variantStrength, $variantQuality, $variantPhotoFormat)) {
    $themedCombo.DrawMode = 'OwnerDrawFixed'
    $themedCombo.ItemHeight = 20
    $themedCombo.Add_DrawItem({
        $isSelected = ($_.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $background = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($(if ($isSelected) { $script:appPalette.Hover } else { $script:appPalette.Input })))
        $_.Graphics.FillRectangle($background, $_.Bounds)
        $background.Dispose()
        $text = if ($_.Index -ge 0) { [string]$this.Items[$_.Index] } else { $this.Text }
        $rect = New-Object System.Drawing.Rectangle(($_.Bounds.X + 5), $_.Bounds.Y, ($_.Bounds.Width - 6), $_.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $text, $form.Font, $rect, [System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Text), [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix)
    })
}

$modeTabs.DrawMode = 'OwnerDrawFixed'
$modeTabs.ItemSize = New-Object System.Drawing.Size(235, 38)
$modeTabs.SizeMode = 'Fixed'
$modeTabs.Add_DrawItem({
    $bounds = $_.Bounds
    $selected = $_.Index -eq $modeTabs.SelectedIndex
    $background = [System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Background)
    $foreground = [System.Drawing.ColorTranslator]::FromHtml($(if ($selected) { $script:appPalette.Text } else { $script:appPalette.Muted }))
    $brush = New-Object System.Drawing.SolidBrush($background)
    $_.Graphics.FillRectangle($brush, $bounds)
    $brush.Dispose()
    [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, $modeTabs.TabPages[$_.Index].Text, $form.Font, $bounds, $foreground, [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter)
    if ($selected) {
        $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($script:appPalette.Accent), 3)
        $_.Graphics.DrawLine($pen, $bounds.Left + 12, $bounds.Bottom - 3, $bounds.Right - 12, $bounds.Bottom - 3)
        $pen.Dispose()
    }
})
$themeLightButton.Add_Click({ Set-AppTheme 'Light'; [void](Save-Settings $settings) })
$themeDarkButton.Add_Click({ Set-AppTheme 'Dark'; [void](Save-Settings $settings) })

# Keep the existing export controls, while giving their crowded rows proper space.
$dropPanel.Location = New-Object System.Drawing.Point(16, 72)
$dropPanel.Size = New-Object System.Drawing.Size(892, 54)
$dropLabel.Location = New-Object System.Drawing.Point(310, 14)
$list.Location = New-Object System.Drawing.Point(16, 138)
$list.Size = New-Object System.Drawing.Size(892, 120)
foreach ($button in @($addButton, $folderButton, $clearButton, $previewButton, $openOutputButton)) { $button.Top = 270 }
$deviceGroup.Location = New-Object System.Drawing.Point(16, 316)
$deviceGroup.Size = New-Object System.Drawing.Size(892, 176)
foreach ($control in @($makeBox, $modelBox, $lensBox, $makeLabel, $modelLabel, $lensLabel)) { $control.Top -= 8 }
foreach ($control in @($latBox, $lonBox, $latLabel, $lonLabel, $backupCheck)) { $control.Top -= 14 }
$favoriteToggleButton.Top = 130
$deviceStatus.Top = 135
$videoGroup.Location = New-Object System.Drawing.Point(16, 504)
$videoGroup.Size = New-Object System.Drawing.Size(892, 176)
$videoModeLabel.Location = New-Object System.Drawing.Point(345, 30)
$videoModeBox.Location = New-Object System.Drawing.Point(445, 26)
$videoModeBox.Size = New-Object System.Drawing.Size(430, 26)
$neutralNameCheck.Location = New-Object System.Drawing.Point(14, 65)
$keepOriginalCheck.Location = New-Object System.Drawing.Point(14, 95)
$outputLabel.Location = New-Object System.Drawing.Point(14, 135)
$outputBox.Location = New-Object System.Drawing.Point(132, 130)
$outputBox.Size = New-Object System.Drawing.Size(656, 24)
$outputButton.Location = New-Object System.Drawing.Point(800, 126)
foreach ($control in @($processButton, $retryRunButton, $cancelButton)) { $control.Top = 694; $control.Height = 38 }
$toolStatus.Top = 706
$progress.Top = 744
$progress.Height = 12
$log.Top = 768
$log.Height = 70
$form.Add_Shown({
    $appCredit.Location = New-Object System.Drawing.Point(($appFooter.ClientSize.Width - $appCredit.Width - 18), 48)
    $footerNote.Location = New-Object System.Drawing.Point(($appFooter.ClientSize.Width - $footerNote.Width - 18), 16)
})
Set-AppTheme $settings.Theme
