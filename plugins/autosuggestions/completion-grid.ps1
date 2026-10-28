# The Tab completion grid of the autosuggestions plugin. It replaces only
# PSReadLine's completion menu (MenuComplete), which draws the selected entry
# and the completed text on the command line with one shared Selection color
# and keeps an entry's own color when it is selected. This grid:
#   - selects in reverse video of the theme's default colors (default text
#     color as background, terminal background as text), for every entry,
#   - leaves the completed text on the command line in the normal colors,
#   - keeps the folder/executable/archive colors for the other entries.
# Keys: Tab/Down next, Shift+Tab/Up previous, Left/Right change column,
#       Enter accept, Esc/Backspace/Ctrl+g undo, Ctrl+c cancel the line,
#       any other character accepts the selection and is typed.
# It uses a few PSReadLine internals to know where the command line is on
# screen; when they are missing, Tab falls back to PSReadLine's menu.

$global:PS10K_GRID = @{
    Selected = "$([char]27)[39;49;7m"
    Unselect = "$([char]27)[27m"
}

# Reflection handles for the PSReadLine internals the grid needs, or $null.
function global:_ps10k_grid_internals {
    if ($global:_ps10k_grid_rl) { return $global:_ps10k_grid_rl }
    try {
        $type = [Microsoft.PowerShell.PSConsoleReadLine]
        $flags = [Reflection.BindingFlags]'NonPublic, Instance'
        $singleton = $type.GetField('_singleton', [Reflection.BindingFlags]'NonPublic, Static').GetValue($null)
        $rl = @{
            Singleton      = $singleton
            InitialY       = $type.GetField('_initialY', $flags)
            PreviousRender = $type.GetField('_previousRender', $flags)
            EndOfBuffer    = $type.GetMethod('EndOfBufferPosition', $flags)
        }
        if (-not ($singleton -and $rl.InitialY -and $rl.PreviousRender -and $rl.EndOfBuffer)) { return $null }
        $render = $rl.PreviousRender.GetValue($singleton)
        if (-not $render) { return $null }
        $rl.RenderInitialY = $render.GetType().GetField('initialY')
        $rl.RenderCursorTop = $render.GetType().GetField('cursorTop')
        if (-not ($rl.RenderInitialY -and $rl.RenderCursorTop)) { return $null }
        $global:_ps10k_grid_rl = $rl
        $rl
    }
    catch { $null }
}

# Row on which the command line ends.
function global:_ps10k_grid_end_row($Rl) {
    $point = $Rl.EndOfBuffer.Invoke($Rl.Singleton, @())
    [int]$point.GetType().GetField('Y').GetValue($point)
}

# After the screen scrolled up by $Lines, tells PSReadLine where its input is
# now (PSReadLine's own menu adjusts the same fields).
function global:_ps10k_grid_shift($Rl, [int]$Lines) {
    $Rl.InitialY.SetValue($Rl.Singleton, [int]$Rl.InitialY.GetValue($Rl.Singleton) - $Lines)
    $render = $Rl.PreviousRender.GetValue($Rl.Singleton)
    $Rl.RenderInitialY.SetValue($render, [int]$Rl.RenderInitialY.GetValue($render) - $Lines)
    $Rl.RenderCursorTop.SetValue($render, [int]$Rl.RenderCursorTop.GetValue($render) - $Lines)
}

# Column-major layout, the same as PSReadLine's menu.
function global:_ps10k_grid_layout([string[]]$Items, [int]$Width) {
    $longest = ($Items | ForEach-Object { _ps10k_width $_ } | Measure-Object -Maximum).Maximum
    $columnWidth = [Math]::Min($longest + 2, $Width)
    $columns = [Math]::Max(1, [Math]::Floor($Width / $columnWidth))
    @{ ColumnWidth = [int]$columnWidth; Columns = [int]$columns; Rows = [int][Math]::Ceiling($Items.Count / $columns) }
}

# One cell: the name padded (or cut) to the column, colored or selected.
function global:_ps10k_grid_cell([string]$Text, [string]$Color, [bool]$Selected, [int]$ColumnWidth) {
    $cell = $ColumnWidth - 1
    if ((_ps10k_width $Text) -gt $cell) { $Text = $Text.Substring(0, [Math]::Max(0, $cell - 3)) + '...' }
    $padding = ' ' * [Math]::Max(0, $cell - (_ps10k_width $Text))
    if ($Selected) { return $global:PS10K_GRID.Selected + $Text + $global:PS10K_GRID.Unselect + $padding + ' ' }
    if ($Color) { return $Color + $Text + "$([char]27)[39m" + $padding + ' ' }
    $Text + $padding + ' '
}

# Text of each grid row.
function global:_ps10k_grid_lines($Grid) {
    $esc = [char]27
    for ($row = 0; $row -lt $Grid.Layout.Rows; $row++) {
        $line = "$esc[0m"
        for ($column = 0; $column -lt $Grid.Layout.Columns; $column++) {
            $index = $column * $Grid.Layout.Rows + $row
            if ($index -ge $Grid.Items.Count) { break }
            $line += _ps10k_grid_cell $Grid.Items[$index] $Grid.Colors[$index] ($index -eq $Grid.Selected) $Grid.Layout.ColumnWidth
        }
        $line
    }
}

# Draws the grid below the command line, scrolling the screen if needed, and
# clears rows left over from a previous, lower position.
function global:_ps10k_grid_draw($Grid) {
    $esc = [char]27
    $left = [Console]::CursorLeft; $top = [Console]::CursorTop
    $first = (_ps10k_grid_end_row $Grid.Rl) + 1
    $overflow = $first + $Grid.Layout.Rows - [Console]::BufferHeight
    if ($overflow -gt 0) {
        [Console]::SetCursorPosition(0, [Console]::BufferHeight - 1)
        [Console]::Write("`n" * $overflow)
        _ps10k_grid_shift $Grid.Rl $overflow
        $first -= $overflow; $top -= $overflow
        if ($null -ne $Grid.Top) { $Grid.Top -= $overflow }
    }
    $lines = @(_ps10k_grid_lines $Grid)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        [Console]::SetCursorPosition(0, $first + $i)
        [Console]::Write($lines[$i] + "$esc[K")
    }
    if ($null -ne $Grid.Top) {
        $oldEnd = $Grid.Top + $Grid.Layout.Rows
        for ($row = $first + $lines.Count; $row -lt $oldEnd -and $row -lt [Console]::BufferHeight; $row++) {
            [Console]::SetCursorPosition(0, $row); [Console]::Write("$esc[2K")
        }
    }
    $Grid.Top = $first
    [Console]::SetCursorPosition($left, $top)
}

function global:_ps10k_grid_clear($Grid) {
    if ($null -eq $Grid.Top) { return }
    $esc = [char]27
    $left = [Console]::CursorLeft; $top = [Console]::CursorTop
    for ($row = $Grid.Top; $row -lt $Grid.Top + $Grid.Layout.Rows -and $row -lt [Console]::BufferHeight; $row++) {
        [Console]::SetCursorPosition(0, $row); [Console]::Write("$esc[2K")
    }
    [Console]::SetCursorPosition($left, $top)
    $Grid.Top = $null
}

# Puts a completion on the command line, rendered like typed text.
function global:_ps10k_grid_apply($Grid, [string]$Text) {
    if (Get-Command _ps10k_hl_update -ErrorAction Ignore) {
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        try { [void](_ps10k_hl_update ($line.Remove($Grid.Start, $Grid.Length).Insert($Grid.Start, $Text))) } catch { }
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($Grid.Start, $Grid.Length, $Text)
    $Grid.Length = $Text.Length
}

# Colors per entry: folders, executables and archives (syntax-highlighting).
function global:_ps10k_grid_colors($Results, [string[]]$Items) {
    if (-not (Get-Command _ps10k_hl_completion_color -ErrorAction Ignore)) { return @($Items | ForEach-Object { $null }) }
    $folderColor = _ps10k_hl_folder_color
    for ($i = 0; $i -lt $Results.Count; $i++) {
        $plain = New-Object System.Management.Automation.CompletionResult($Results[$i].CompletionText, $Items[$i], $Results[$i].ResultType, $Items[$i])
        _ps10k_hl_completion_color $plain $folderColor
    }
}

# Completes at the cursor. Returns 'done', 'cycle' (the grid does not fit:
# cycle in place instead) or 'menu' (internals missing: use PSReadLine's menu).
function global:_ps10k_grid_complete([string]$Line, [int]$Cursor, [bool]$Backward) {
    $rl = _ps10k_grid_internals
    if (-not $rl) { return 'menu' }
    $completion = TabExpansion2 -inputScript $Line -cursorColumn $Cursor
    $results = @($completion.CompletionMatches)
    if ($results.Count -eq 0) { [Microsoft.PowerShell.PSConsoleReadLine]::Ding(); return 'done' }
    $start = $completion.ReplacementIndex; $length = $completion.ReplacementLength
    if ($results.Count -eq 1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $length, $results[0].CompletionText)
        return 'done'
    }

    $items = @($results | ForEach-Object { _ps10k_strip_ansi $_.ListItemText })
    $layout = _ps10k_grid_layout $items ([Console]::BufferWidth)
    $promptTop = [int]$rl.InitialY.GetValue($rl.Singleton) - [int](Get-PSReadLineOption).ExtraPromptLineCount
    $inputRows = (_ps10k_grid_end_row $rl) - $promptTop + 1
    # One spare row: the command line can wrap while the grid is open.
    if ($inputRows + 1 + $layout.Rows -gt [Console]::WindowHeight) { return 'cycle' }

    $count = $results.Count
    $grid = @{
        Rl = $rl; Items = $items; Colors = @(_ps10k_grid_colors $results $items); Layout = $layout; Top = $null
        Start = $start; Length = $length; Original = $Line.Substring($start, $length)
        Selected = $(if ($Backward) { $count - 1 } else { 0 })
    }
    try {
        _ps10k_grid_apply $grid $results[$grid.Selected].CompletionText
        _ps10k_grid_draw $grid
        while ($true) {
            $key = [Console]::ReadKey($true)
            $shift = ($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
            $control = ($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0
            $alt = ($key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0
            $next = $grid.Selected
            switch ($key.Key) {
                'Tab' { $next = if ($shift) { ($next - 1 + $count) % $count } else { ($next + 1) % $count } }
                'DownArrow' { $next = ($next + 1) % $count }
                'UpArrow' { $next = ($next - 1 + $count) % $count }
                'RightArrow' { if ($next + $layout.Rows -lt $count) { $next += $layout.Rows } }
                'LeftArrow' { if ($next - $layout.Rows -ge 0) { $next -= $layout.Rows } }
                'Enter' { return 'done' }
                'Escape' { _ps10k_grid_apply $grid $grid.Original; return 'done' }
                'Backspace' { _ps10k_grid_apply $grid $grid.Original; return 'done' }
                default {
                    if ($control -and $key.Key -eq 'C') {
                        _ps10k_grid_clear $grid
                        [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine()
                        return 'done'
                    }
                    if ($control -and $key.Key -eq 'G') { _ps10k_grid_apply $grid $grid.Original; return 'done' }
                    if (-not $control -and -not $alt -and [int]$key.KeyChar -ge 32) {
                        _ps10k_grid_clear $grid
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
                    }
                    return 'done'
                }
            }
            if ($next -ne $grid.Selected) {
                $grid.Selected = $next
                _ps10k_grid_apply $grid $results[$next].CompletionText
                _ps10k_grid_draw $grid
            }
        }
    }
    finally { _ps10k_grid_clear $grid }
}
