# The autosuggestions plugin: Tab completion and its grid.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'Tab falls back to in-place cycling when the menu cannot fit' {
    Assert-Equal 1 (_ps10k_menu_rows (@('aaaaaaaa') * 10) 100) 'ten short items in one row'
    Assert-Equal 13 (_ps10k_menu_rows (@('aaaaaaaa') * 25) 20) 'two columns of 8+2 cells'
    Assert-Equal 3 (_ps10k_menu_rows @('a', 'b', 'c') 2) 'one column when items are wider than the window'
    Assert-Equal 0 (_ps10k_menu_rows @() 80)
    $tab = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Tab' } | Select-Object -First 1
    Assert-Equal 'PS10kTabComplete' $tab.Function
}

Test-Case 'completion runs with Ctrl+c as a key and restores the console mode' {
    $before = try { [Console]::TreatControlCAsInput } catch { $null }
    function Invoke-Handler($key) { _ps10k_with_readline_input { "got $key" } }
    Assert-Equal 'got Tab' (Invoke-Handler 'Tab') 'the action sees the handler variables'
    try { _ps10k_with_readline_input { throw 'boom' } } catch { }
    $after = try { [Console]::TreatControlCAsInput } catch { $null }
    Assert-Equal $before $after 'console mode restored after an error'
    $tab = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Tab' } | Select-Object -First 1
    Assert-Equal 'PS10kTabComplete' $tab.Function
}

Test-Case 'completion grid colors folders, executables and archives' {
    $dir = Join-Path $work 'grid'
    New-Item -ItemType Directory -Path (Join-Path $dir 'folder') -Force | Out-Null
    foreach ($name in 'tool.exe', 'run.ps1', 'pack.zip', 'notes.txt') { Set-Content -LiteralPath (Join-Path $dir $name) -Value 'x' }
    Push-Location $dir
    try {
        $line = 'Get-ChildItem .\'
        $completion = TabExpansion2 -inputScript $line -cursorColumn $line.Length
        $byText = @{}
        foreach ($r in $completion.CompletionMatches) { $byText[(_ps10k_strip_ansi $r.ListItemText)] = $r }
        $esc = [char]27
        Assert-True $byText['folder'].ListItemText.StartsWith((_ps10k_hl_folder_color)) 'folder color'
        Assert-True $byText['tool.exe'].ListItemText.StartsWith($global:PS10K_HL.Valid) 'executable green'
        Assert-True $byText['run.ps1'].ListItemText.StartsWith($global:PS10K_HL.Valid) 'script green'
        Assert-True $byText['pack.zip'].ListItemText.StartsWith($global:PS10K_HL.Invalid) 'archive red'
        Assert-Equal 'notes.txt' $byText['notes.txt'].ListItemText 'plain files stay uncolored'
        Assert-True $byText['tool.exe'].ListItemText.EndsWith("$esc[39m") 'only the foreground is reset'
        Assert-Equal '.\tool.exe' $byText['tool.exe'].CompletionText 'the inserted text has no colors'
        Assert-Equal 8 (_ps10k_width $byText['tool.exe'].ListItemText) 'width ignores the colors'
    }
    finally { Pop-Location }
}

Test-Case 'completion grid selects in reverse video without entry colors' {
    $esc = [char]27
    $blue = "$esc[38;5;31m"
    $selected = _ps10k_grid_cell 'vim' $blue $true 15
    Assert-True $selected.StartsWith("$esc[39;49;7mvim$esc[27m") 'reverse video of the default colors'
    Assert-True (-not $selected.Contains($blue)) 'a selected folder loses its color'
    Assert-Equal 15 (_ps10k_width $selected) 'cell keeps the column width'
    $plain = _ps10k_grid_cell 'vim' $blue $false 15
    Assert-True $plain.StartsWith("$($blue)vim$esc[39m") 'other folders keep their color'
    Assert-Equal 'very-long-f... ' (_ps10k_grid_cell 'very-long-folder-name' $null $false 15) 'long names are cut to the column'

    $layout = _ps10k_grid_layout @('powershell10k', 'vim', 'xwax') 80
    Assert-Equal 15 $layout.ColumnWidth
    Assert-Equal 1 $layout.Rows
    $grid = @{ Items = @('powershell10k', 'vim', 'xwax'); Colors = @($blue, $blue, $blue); Layout = $layout; Selected = 1 }
    $lines = @(_ps10k_grid_lines $grid)
    Assert-Equal 1 $lines.Count
    Assert-Equal 'powershell10k  vim  xwax' (_ps10k_strip_ansi $lines[0]).TrimEnd() 'each column as wide as its own entries'
    $long = @('a' * 92) + @(1..20 | ForEach-Object { "name$_" })
    $packed = _ps10k_grid_layout $long 120
    Assert-True ($packed.Columns -gt 1) 'a very long name does not force a single column'
    Assert-True (($packed.ColumnWidths | Measure-Object -Sum).Sum -le 120) 'the grid fits the width'
    Assert-Equal 42 $packed.ColumnWidths[0] 'long names are cut to a third of the width'
    $column = (_ps10k_grid_layout (1..10 | ForEach-Object { "item$_" }) 16)
    Assert-Equal 2 $column.Columns 'two columns of 6+2 cells'
    Assert-Equal 5 $column.Rows
    Assert-True ($null -eq (_ps10k_rl_internals) -or (_ps10k_rl_internals).EndOfBuffer) 'internals are found or cleanly missing'
    $shiftTab = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Shift+Tab' } | Select-Object -First 1
    Assert-Equal 'PS10kTabCompleteBackward' $shiftTab.Function
}

Test-Case 'completion adds the folder separator like zsh' {
    function New-Result($Text, $Type) { New-Object System.Management.Automation.CompletionResult($Text, $Text, $Type, $Text) }
    Assert-Equal '.\Workspace\' (_ps10k_grid_text (New-Result '.\Workspace' 'ProviderContainer') '\')
    Assert-Equal './Workspace/' (_ps10k_grid_text (New-Result './Workspace' 'ProviderContainer') '/')
    Assert-Equal "'.\My Folder\'" (_ps10k_grid_text (New-Result "'.\My Folder'" 'ProviderContainer') '\') 'inside the quotes'
    Assert-Equal '.\Workspace\' (_ps10k_grid_text (New-Result '.\Workspace\' 'ProviderContainer') '\') 'not doubled'
    Assert-Equal '.\notes.txt' (_ps10k_grid_text (New-Result '.\notes.txt' 'ProviderItem') '\') 'files unchanged'
    Assert-Equal 'Get-ChildItem' (_ps10k_grid_text (New-Result 'Get-ChildItem' 'Command') '\') 'commands unchanged'
    Assert-Equal '/' (_ps10k_grid_separator 'src/li')
    Assert-Equal '\' (_ps10k_grid_separator 'src\li')
    Assert-Equal '\' (_ps10k_grid_separator 'Wo')
}

Test-Case 'completion grid scrolls when it is taller than the window' {
    $items = @(1..40 | ForEach-Object { "entry$_" })
    $grid = @{ Items = $items; Colors = @($items | ForEach-Object { $null }); Layout = (_ps10k_grid_layout $items 9); Selected = 0 }
    Assert-Equal 40 $grid.Layout.Rows 'one column'
    _ps10k_grid_viewport $grid 10
    Assert-True $grid.Paged
    Assert-Equal 9 $grid.Visible 'one row for the status line'
    $lines = @(_ps10k_grid_lines $grid)
    Assert-Equal 10 $lines.Count
    Assert-Equal 'rows 1-9 of 40' (_ps10k_strip_ansi $lines[-1])
    $grid.Selected = 15; _ps10k_grid_scroll_to $grid
    Assert-Equal 7 $grid.Offset 'selected row is the last shown row'
    Assert-Equal 'entry16' (_ps10k_strip_ansi @(_ps10k_grid_lines $grid)[8]).Trim()
    $grid.Selected = 2; _ps10k_grid_scroll_to $grid
    Assert-Equal 2 $grid.Offset 'scrolls back up'
    $small = @{ Items = @('a', 'b'); Colors = @($null, $null); Layout = (_ps10k_grid_layout @('a', 'b') 80); Selected = 0 }
    _ps10k_grid_viewport $small 10
    Assert-True (-not $small.Paged) 'a grid that fits has no status line'
    Assert-Equal 1 @(_ps10k_grid_lines $small).Count
}

Test-Case 'grid keys move the selection and wrap around' {
    function New-Key([ConsoleKey]$Key, [switch]$Shift, [char]$Char = [char]0) { New-Object ConsoleKeyInfo($Char, $Key, $Shift, $false, $false) }
    # 7 entries in 3 rows: columns 0-2, 3-5, 6
    $grid = @{ Items = @(1..7); Layout = @{ Rows = 3 }; Selected = 0 }
    Assert-Equal 1 (_ps10k_grid_move $grid (New-Key Tab))
    Assert-Equal 6 (_ps10k_grid_move $grid (New-Key Tab -Shift)) 'Shift+Tab wraps to the end'
    Assert-Equal 6 (_ps10k_grid_move $grid (New-Key UpArrow))
    Assert-Equal 3 (_ps10k_grid_move $grid (New-Key RightArrow)) 'next column'
    Assert-Equal 0 (_ps10k_grid_move $grid (New-Key LeftArrow)) 'no column to the left: stays'
    $grid.Selected = 6
    Assert-Equal 0 (_ps10k_grid_move $grid (New-Key DownArrow)) 'Down wraps to the start'
    Assert-Equal 6 (_ps10k_grid_move $grid (New-Key RightArrow)) 'no column to the right: stays'
    Assert-Equal 3 (_ps10k_grid_move $grid (New-Key LeftArrow))
    foreach ($key in 'Enter', 'Escape', 'Backspace', 'A') { Assert-Equal -1 (_ps10k_grid_move $grid (New-Key $key)) "$key closes the grid" }
}

Test-Case 'grid colors match the highlighting rules' {
    $dir = Join-Path $work 'grid-colors'
    New-Item -ItemType Directory -Path (Join-Path $dir 'sub') -Force | Out-Null
    foreach ($name in 'a.exe', 'b.zip', 'c.txt') { Set-Content -LiteralPath (Join-Path $dir $name) -Value 'x' }
    Push-Location -LiteralPath $dir
    try {
        $results = @((& $global:_ps10k_tabexpansion2 -inputScript 'ls ' -cursorColumn 3).CompletionMatches)
        $items = @($results | ForEach-Object { $_.ListItemText })
        $colors = _ps10k_grid_colors $results $items
        $folder = _ps10k_hl_folder_color
        for ($i = 0; $i -lt $results.Count; $i++) {
            $plain = New-Object System.Management.Automation.CompletionResult($results[$i].CompletionText, $items[$i], $results[$i].ResultType, $items[$i])
            Assert-Equal "$(_ps10k_hl_completion_color $plain $folder)" "$($colors[$i])" "same color for $($items[$i])"
        }
        Assert-True (_ps10k_menu_fits 'ls ' 3) 'four entries fit'
        Assert-Equal 2 (_ps10k_grid_column_width @{ Layout = @{ Rows = 2; ColumnWidths = @(5, 2) } } 3)
        Assert-Equal 7 (_ps10k_grid_text_width @{ Widths = @(1, 7) } 1)
        Assert-Equal -1 (_ps10k_grid_text_width @{} 0) 'unknown width'
    }
    finally { Pop-Location }
}
