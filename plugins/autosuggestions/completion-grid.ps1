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

# Column-major layout like zsh: each column is as wide as its longest entry,
# and names longer than a third of the window are cut, so one long name does
# not force everything into a single column. Tries the most columns first.
function global:_ps10k_grid_layout([string[]]$Items, [int]$Width) {
    $cap = [Math]::Max(16, [Math]::Floor($Width / 3))
    $widths = @($Items | ForEach-Object { [Math]::Min((_ps10k_width $_), $cap) })
    $count = $widths.Count
    $narrowest = ($widths | Measure-Object -Minimum).Minimum
    $tryColumns = [Math]::Max(1, [Math]::Min($count, [Math]::Floor($Width / ($narrowest + 2))))
    for ($columns = $tryColumns; $columns -ge 1; $columns--) {
        $rows = [int][Math]::Ceiling($count / $columns)
        $used = [int][Math]::Ceiling($count / $rows)
        $columnWidths = @(for ($c = 0; $c -lt $used; $c++) {
            $slice = $widths[($c * $rows)..([Math]::Min($count, ($c + 1) * $rows) - 1)]
            [int](($slice | Measure-Object -Maximum).Maximum + 2)
        })
        if (($columnWidths | Measure-Object -Sum).Sum -le $Width -or $columns -eq 1) {
            $columnWidths = @($columnWidths | ForEach-Object { [Math]::Min($_, $Width) })
            return @{
                Columns = $used; Rows = $rows; ColumnWidths = $columnWidths
                ColumnWidth = [int](($columnWidths | Measure-Object -Maximum).Maximum)
            }
        }
    }
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

# How many grid rows fit below the command line. A grid taller than that
# scrolls: only $Visible rows are shown, plus a status line.
function global:_ps10k_grid_viewport($Grid, [int]$Available) {
    if ($Grid.Layout.Rows -le $Available) {
        $Grid.Visible = $Grid.Layout.Rows; $Grid.Paged = $false
    }
    else {
        $Grid.Visible = [Math]::Max(1, $Available - 1); $Grid.Paged = $true
    }
    $Grid.Offset = 0
    _ps10k_grid_scroll_to $Grid
}

# Scrolls the shown rows so that the selected entry is visible.
function global:_ps10k_grid_scroll_to($Grid) {
    $row = $Grid.Selected % $Grid.Layout.Rows
    if ($row -lt $Grid.Offset) { $Grid.Offset = $row }
    if ($row -ge $Grid.Offset + $Grid.Visible) { $Grid.Offset = $row - $Grid.Visible + 1 }
}

# Text of each shown grid row, plus the status line of a scrolling grid.
function global:_ps10k_grid_lines($Grid) {
    $esc = [char]27
    $visible = if ($Grid.Visible) { $Grid.Visible } else { $Grid.Layout.Rows }
    $offset = if ($Grid.Offset) { $Grid.Offset } else { 0 }
    for ($row = $offset; $row -lt [Math]::Min($Grid.Layout.Rows, $offset + $visible); $row++) {
        $line = "$esc[0m"
        for ($column = 0; $column -lt $Grid.Layout.Columns; $column++) {
            $index = $column * $Grid.Layout.Rows + $row
            if ($index -ge $Grid.Items.Count) { break }
            $line += _ps10k_grid_cell $Grid.Items[$index] $Grid.Colors[$index] ($index -eq $Grid.Selected) $Grid.Layout.ColumnWidths[$column]
        }
        $line
    }
    if ($Grid.Paged) {
        # The scheme's bright black, like comments.
        "$esc[0m$esc[90mrows $($offset + 1)-$($offset + $visible) of $($Grid.Layout.Rows)$esc[39m"
    }
}

# Draws the grid below the command line, scrolling the screen if needed, and
# clears rows left over from a previous, lower position.
function global:_ps10k_grid_draw($Grid) {
    $esc = [char]27
    $left = [Console]::CursorLeft; $top = [Console]::CursorTop
    $lines = @(_ps10k_grid_lines $Grid)
    $first = (_ps10k_grid_end_row $Grid.Rl) + 1
    $overflow = $first + $lines.Count - [Console]::BufferHeight
    if ($overflow -gt 0) {
        [Console]::SetCursorPosition(0, [Console]::BufferHeight - 1)
        [Console]::Write("`n" * $overflow)
        _ps10k_grid_shift $Grid.Rl $overflow
        $first -= $overflow; $top -= $overflow
        if ($null -ne $Grid.Top) { $Grid.Top -= $overflow }
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        [Console]::SetCursorPosition(0, $first + $i)
        [Console]::Write($lines[$i] + "$esc[K")
    }
    # The command line may have become shorter, leaving old grid rows behind.
    if ($null -ne $Grid.Top) {
        $oldEnd = $Grid.Top + $Grid.Height
        for ($row = $first + $lines.Count; $row -lt $oldEnd -and $row -lt [Console]::BufferHeight; $row++) {
            [Console]::SetCursorPosition(0, $row); [Console]::Write("$esc[2K")
        }
    }
    $Grid.Top = $first
    $Grid.Height = $lines.Count
    [Console]::SetCursorPosition($left, $top)
}

function global:_ps10k_grid_clear($Grid) {
    if ($null -eq $Grid.Top) { return }
    $esc = [char]27
    $left = [Console]::CursorLeft; $top = [Console]::CursorTop
    for ($row = $Grid.Top; $row -lt $Grid.Top + $Grid.Height -and $row -lt [Console]::BufferHeight; $row++) {
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

# Like zsh, a folder is completed with its separator ('Workspace\'), so the
# next Tab lists what is inside. Quoted folders get it inside the quotes.
function global:_ps10k_grid_text($Result, [string]$Separator) {
    $text = $Result.CompletionText
    if ($Result.ResultType -ne 'ProviderContainer' -or -not $text) { return $text }
    $quote = $text[-1]
    if (($quote -eq "'" -or $quote -eq '"') -and $text.Length -ge 2 -and $text[0] -eq $quote) {
        $inner = $text.Substring(0, $text.Length - 1)
        if ($inner.EndsWith('\') -or $inner.EndsWith('/')) { return $text }
        return $inner + $Separator + $quote
    }
    if ($text.EndsWith('\') -or $text.EndsWith('/')) { return $text }
    $text + $Separator
}

# The separator the user is typing with: '/' when the word only uses '/'.
function global:_ps10k_grid_separator([string]$Word) {
    if ($Word.Contains('/') -and -not $Word.Contains('\')) { return '/' }
    '\'
}

# Completes at the cursor. Returns 'done', 'cycle' (not even a row of the grid
# fits: cycle in place instead) or 'menu' (internals missing: PSReadLine's menu).
function global:_ps10k_grid_complete([string]$Line, [int]$Cursor, [bool]$Backward) {
    $rl = _ps10k_grid_internals
    if (-not $rl) { return 'menu' }
    $completion = TabExpansion2 -inputScript $Line -cursorColumn $Cursor
    $results = @($completion.CompletionMatches)
    if ($results.Count -eq 0) { [Microsoft.PowerShell.PSConsoleReadLine]::Ding(); return 'done' }
    $start = $completion.ReplacementIndex; $length = $completion.ReplacementLength
    $original = $Line.Substring($start, $length)
    $separator = _ps10k_grid_separator $original
    $texts = @($results | ForEach-Object { _ps10k_grid_text $_ $separator })
    if ($results.Count -eq 1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $length, $texts[0])
        return 'done'
    }

    $items = @($results | ForEach-Object { _ps10k_strip_ansi $_.ListItemText })
    $layout = _ps10k_grid_layout $items ([Console]::BufferWidth)
    $promptTop = [int]$rl.InitialY.GetValue($rl.Singleton) - [int](Get-PSReadLineOption).ExtraPromptLineCount
    $inputRows = (_ps10k_grid_end_row $rl) - $promptTop + 1
    # One spare row: the command line can wrap while the grid is open.
    $available = [Console]::WindowHeight - $inputRows - 1
    if ($available -lt 2) { return 'cycle' }

    $count = $results.Count
    $grid = @{
        Rl = $rl; Items = $items; Colors = @(_ps10k_grid_colors $results $items); Layout = $layout
        Top = $null; Height = 0
        Start = $start; Length = $length; Original = $original
        Selected = $(if ($Backward) { $count - 1 } else { 0 })
    }
    _ps10k_grid_viewport $grid $available
    try {
        _ps10k_grid_apply $grid $texts[$grid.Selected]
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
                        # A typed separator after a folder's added one is not doubled.
                        $current = $texts[$grid.Selected]
                        $typedSeparator = $key.KeyChar -eq '\' -or $key.KeyChar -eq '/'
                        if (-not ($typedSeparator -and ($current.EndsWith('\') -or $current.EndsWith('/')))) {
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
                        }
                    }
                    return 'done'
                }
            }
            if ($next -ne $grid.Selected) {
                $grid.Selected = $next
                _ps10k_grid_scroll_to $grid
                _ps10k_grid_apply $grid $texts[$next]
                _ps10k_grid_draw $grid
            }
        }
    }
    finally { _ps10k_grid_clear $grid }
}
