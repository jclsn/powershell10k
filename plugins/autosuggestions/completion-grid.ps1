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
# Plain loops: this runs on every Tab, and pipelines are slow in PowerShell.
function global:_ps10k_grid_layout([string[]]$Items, [int]$Width, [int[]]$Widths) {
    if (-not $Widths) { $Widths = @(foreach ($item in $Items) { _ps10k_width $item }) }
    $cap = [Math]::Max(16, [Math]::Floor($Width / 3))
    $count = $Widths.Count
    $capped = New-Object int[] $count
    $narrowest = [int]::MaxValue
    for ($i = 0; $i -lt $count; $i++) {
        $w = [Math]::Min($Widths[$i], $cap)
        $capped[$i] = $w
        if ($w -lt $narrowest) { $narrowest = $w }
    }
    $tryColumns = [Math]::Max(1, [Math]::Min($count, [Math]::Floor($Width / ($narrowest + 2))))
    for ($columns = $tryColumns; $columns -ge 1; $columns--) {
        $rows = [int][Math]::Ceiling($count / $columns)
        $used = [int][Math]::Ceiling($count / $rows)
        $columnWidths = New-Object int[] $used
        $sum = 0; $widest = 0
        for ($c = 0; $c -lt $used; $c++) {
            $max = 0
            $end = [Math]::Min($count, ($c + 1) * $rows)
            for ($i = $c * $rows; $i -lt $end; $i++) { if ($capped[$i] -gt $max) { $max = $capped[$i] } }
            $columnWidths[$c] = [Math]::Min($max + 2, $Width)
            $sum += $columnWidths[$c]
            if ($columnWidths[$c] -gt $widest) { $widest = $columnWidths[$c] }
            if ($sum -gt $Width -and $columns -gt 1) { break }
        }
        if ($sum -le $Width -or $columns -eq 1) {
            return @{ Columns = $used; Rows = $rows; ColumnWidths = $columnWidths; ColumnWidth = $widest }
        }
    }
}

# One cell: the name padded (or cut) to the column, colored or selected.
# $TextWidth saves measuring the name again when it is already known.
function global:_ps10k_grid_cell([string]$Text, [string]$Color, [bool]$Selected, [int]$ColumnWidth, [int]$TextWidth = -1) {
    $cell = $ColumnWidth - 1
    if ($TextWidth -lt 0) { $TextWidth = _ps10k_width $Text }
    if ($TextWidth -gt $cell) {
        $Text = $Text.Substring(0, [Math]::Max(0, [Math]::Min($Text.Length, $cell - 3))) + '...'
        $TextWidth = _ps10k_width $Text
    }
    $padding = ' ' * [Math]::Max(0, $cell - $TextWidth)
    if ($Selected) { return $global:PS10K_GRID.Selected + $Text + $global:PS10K_GRID.Unselect + $padding + ' ' }
    if ($Color) { return $Color + $Text + "$([char]27)[39m" + $padding + ' ' }
    $Text + $padding + ' '
}

# Builds every entry's cell once, so moving the selection only joins strings.
# The selected look of a cell is built the first time it is selected.
function global:_ps10k_grid_prepare($Grid) {
    $count = $Grid.Items.Count
    $Grid.Normal = New-Object string[] $count
    $Grid.Picked = New-Object string[] $count
    $rows = $Grid.Layout.Rows; $columnWidths = $Grid.Layout.ColumnWidths; $widths = $Grid.Widths
    for ($i = 0; $i -lt $count; $i++) {
        $textWidth = if ($widths) { $widths[$i] } else { -1 }
        $Grid.Normal[$i] = _ps10k_grid_cell $Grid.Items[$i] $Grid.Colors[$i] $false $columnWidths[[Math]::Floor($i / $rows)] $textWidth
    }
}

function global:_ps10k_grid_column_width($Grid, [int]$Index) { $Grid.Layout.ColumnWidths[[Math]::Floor($Index / $Grid.Layout.Rows)] }
function global:_ps10k_grid_text_width($Grid, [int]$Index) { if ($Grid.Widths) { $Grid.Widths[$Index] } else { -1 } }

# Text of one grid row.
function global:_ps10k_grid_row($Grid, [int]$Row) {
    if (-not $Grid.Normal) { _ps10k_grid_prepare $Grid }
    $rows = $Grid.Layout.Rows
    $count = $Grid.Items.Count
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add("$([char]27)[0m")
    for ($index = $Row; $index -lt $count; $index += $rows) {
        if ($index -ne $Grid.Selected) { $parts.Add($Grid.Normal[$index]); continue }
        if (-not $Grid.Picked[$index]) {
            $Grid.Picked[$index] = _ps10k_grid_cell $Grid.Items[$index] $Grid.Colors[$index] $true (_ps10k_grid_column_width $Grid $index) (_ps10k_grid_text_width $Grid $index)
        }
        $parts.Add($Grid.Picked[$index])
    }
    [string]::Concat($parts)
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
        _ps10k_grid_row $Grid $row
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

# Redraws only the given grid rows (the old and the new selection) when the
# grid did not move; otherwise draws it all.
function global:_ps10k_grid_draw_rows($Grid, [int[]]$Rows, [int]$PreviousOffset) {
    $first = (_ps10k_grid_end_row $Grid.Rl) + 1
    if ($null -eq $Grid.Top -or $first -ne $Grid.Top -or $Grid.Offset -ne $PreviousOffset) { return (_ps10k_grid_draw $Grid) }
    $esc = [char]27
    $left = [Console]::CursorLeft; $top = [Console]::CursorTop
    foreach ($row in ($Rows | Select-Object -Unique)) {
        if ($row -lt $Grid.Offset -or $row -ge $Grid.Offset + $Grid.Visible) { continue }
        [Console]::SetCursorPosition(0, $Grid.Top + $row - $Grid.Offset)
        [Console]::Write((_ps10k_grid_row $Grid $row) + "$esc[K")
    }
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

# Colors per entry: folders, executables and archives, the same rules as
# syntax-highlighting's _ps10k_hl_completion_color, with the extension lists
# turned into sets once instead of once per entry.
function global:_ps10k_grid_colors($Results, [string[]]$Items) {
    $colors = New-Object string[] $Results.Count
    if (-not (Get-Command _ps10k_hl_folder_color -ErrorAction Ignore)) { return , $colors }
    $folderColor = _ps10k_hl_folder_color
    $ignoreCase = [StringComparer]::OrdinalIgnoreCase
    $executables = New-Object 'System.Collections.Generic.HashSet[string]' $ignoreCase
    foreach ($extension in @(($env:PATHEXT -split ';') + '.ps1')) { if ($extension) { [void]$executables.Add($extension) } }
    $archives = New-Object 'System.Collections.Generic.HashSet[string]' $ignoreCase
    foreach ($extension in $global:PS10K_HL.Archives) { [void]$archives.Add($extension) }
    for ($i = 0; $i -lt $Results.Count; $i++) {
        $type = $Results[$i].ResultType
        if ($type -eq 'ProviderContainer') { $colors[$i] = $folderColor; continue }
        if ($type -ne 'ProviderItem') { continue }
        $extension = try { [IO.Path]::GetExtension($Items[$i]) } catch { '' }
        if (-not $extension) { continue }
        if ($executables.Contains($extension)) { $colors[$i] = $global:PS10K_HL.Valid }
        elseif ($archives.Contains($extension)) { $colors[$i] = $global:PS10K_HL.Invalid }
    }
    , $colors
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
    # The unwrapped completion: the grid colors entries itself, so the
    # syntax-highlighting wrapper's colored names would only be stripped again.
    $completion = if ($global:_ps10k_tabexpansion2) {
        & $global:_ps10k_tabexpansion2 -inputScript $Line -cursorColumn $Cursor
    }
    else { TabExpansion2 -inputScript $Line -cursorColumn $Cursor }
    $results = @($completion.CompletionMatches)
    if ($results.Count -eq 0) { [Microsoft.PowerShell.PSConsoleReadLine]::Ding(); return 'done' }
    $start = $completion.ReplacementIndex; $length = $completion.ReplacementLength
    $original = $Line.Substring($start, $length)
    $separator = _ps10k_grid_separator $original
    if ($results.Count -eq 1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $length, (_ps10k_grid_text $results[0] $separator))
        return 'done'
    }
    # Inline fast paths: function calls cost more than the work for most entries.
    $texts = @(foreach ($r in $results) {
        $text = $r.CompletionText
        if ($r.ResultType -ne 'ProviderContainer' -or -not $text -or $text.EndsWith('\') -or $text.EndsWith('/')) { $text }
        elseif ($text.EndsWith("'") -or $text.EndsWith('"')) { _ps10k_grid_text $r $separator }
        else { $text + $separator }
    })

    $esc = [char]27
    $items = @(foreach ($r in $results) {
        $name = $r.ListItemText
        if ($name.IndexOf($esc) -ge 0) { _ps10k_strip_ansi $name } else { $name }
    })
    $widths = [int[]]@(foreach ($item in $items) {
        if ($item -cmatch '^[\x20-\x7E]*$') { $item.Length } else { _ps10k_width $item }
    })
    $layout = _ps10k_grid_layout $items ([Console]::BufferWidth) $widths
    $promptTop = [int]$rl.InitialY.GetValue($rl.Singleton) - [int](Get-PSReadLineOption).ExtraPromptLineCount
    $inputRows = (_ps10k_grid_end_row $rl) - $promptTop + 1
    # One spare row: the command line can wrap while the grid is open.
    $available = [Console]::WindowHeight - $inputRows - 1
    if ($available -lt 2) { return 'cycle' }

    $count = $results.Count
    $grid = @{
        Rl = $rl; Items = $items; Widths = $widths; Colors = (_ps10k_grid_colors $results $items); Layout = $layout
        Top = $null; Height = 0
        Start = $start; Length = $length; Original = $original
        Selected = $(if ($Backward) { $count - 1 } else { 0 })
    }
    _ps10k_grid_prepare $grid
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
                $previousRow = $grid.Selected % $layout.Rows
                $previousOffset = $grid.Offset
                $grid.Selected = $next
                _ps10k_grid_scroll_to $grid
                _ps10k_grid_apply $grid $texts[$next]
                _ps10k_grid_draw_rows $grid @($previousRow, ($next % $layout.Rows)) $previousOffset
            }
        }
    }
    finally { _ps10k_grid_clear $grid }
}
