# autosuggestions plugin: history-substring-search and completion on top of
# PSReadLine.
#   Up/Down      search history for lines starting with what you typed
#   Tab          completion grid below the line (completion-grid.ps1); Tab
#                again moves through it. When the grid does not fit in the
#                window, Tab cycles the matches in place instead.
#   Shift+Tab    the same, backwards
# Inline suggestions from history (zsh-autosuggestions) are off, so nothing is
# shown before you press Tab. Turn them on in your profile, before
# powershell10k is loaded, with:
#   $PS10K_AUTOSUGGEST_INLINE = $true   grey suggestion, Right/End accepts it
#   $PS10K_AUTOSUGGEST_LIST = $true     list of suggestions below the line
# Inline suggestions need PSReadLine 2.1+ (install.ps1 installs 2.4.5).

if (Get-Module PSReadLine) {
    $ps10kPsrl = (Get-Module PSReadLine).Version

    Set-PSReadLineOption -HistorySearchCursorMovesToEnd -HistoryNoDuplicates -BellStyle None
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineOption -ShowToolTips:$false

    if ($ps10kPsrl -ge [version]'2.1.0') {
        $ps10kSource = if ($global:PS10K_AUTOSUGGEST_INLINE -or $global:PS10K_AUTOSUGGEST_LIST) { 'History' } else { 'None' }
        # Throws when output is redirected (no virtual terminal), e.g. in scripts.
        try { Set-PSReadLineOption -PredictionSource $ps10kSource } catch { }
        Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]27)[38;5;244m" }
        Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
        Set-PSReadLineKeyHandler -Key End -Function EndOfLine
        Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    }
    if ($ps10kPsrl -ge [version]'2.2.0') {
        $ps10kStyle = if ($global:PS10K_AUTOSUGGEST_LIST) { 'ListView' } else { 'InlineView' }
        try { Set-PSReadLineOption -PredictionViewStyle $ps10kStyle } catch { }
    }
    Remove-Variable -Name ps10kPsrl, ps10kSource, ps10kStyle -ErrorAction SilentlyContinue
}

# Rows the completion menu needs, computed the way PSReadLine does it.
function global:_ps10k_menu_rows([string[]]$Items, [int]$BufferWidth) {
    if (-not $Items) { return 0 }
    $longest = ($Items | ForEach-Object { _ps10k_width $_ } | Measure-Object -Maximum).Maximum
    $columnWidth = [Math]::Min($longest + 2, $BufferWidth)
    $columns = [Math]::Max(1, [Math]::Floor($BufferWidth / $columnWidth))
    [int][Math]::Ceiling($Items.Count / $columns)
}

# PSReadLine only shows a selectable menu when menu, prompt and command line
# fit in the window; otherwise it prints the list once and Tab cannot cycle.
function global:_ps10k_menu_fits([string]$Line, [int]$Cursor) {
    $completion = TabExpansion2 -inputScript $Line -cursorColumn $Cursor
    $items = @($completion.CompletionMatches | ForEach-Object { $_.ListItemText })
    if ($items.Count -le 1) { return $true }
    $ui = $Host.UI.RawUI
    $lines = 1 + ([regex]::Matches($Line, "`n")).Count + [int](Get-PSReadLineOption).ExtraPromptLineCount
    # One spare row: the command line can wrap while the menu is open.
    $lines + 1 + (_ps10k_menu_rows $items $ui.BufferSize.Width) -le $ui.WindowSize.Height
}

. ([IO.Path]::Combine($PSScriptRoot, 'completion-grid.ps1'))

# Tab and Shift+Tab: powershell10k's completion grid; in-place cycling when the
# grid does not fit; PSReadLine's menu when the grid cannot run.
function global:_ps10k_tab_complete($Key, $Arg, [bool]$Backward) {
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $before = $line
    # Still cycling in place: keep going even though the line now holds a match.
    $cycling = $null -ne $global:_ps10k_tab_cycle -and $global:_ps10k_tab_cycle -eq $line
    $outcome = 'cycle'
    if (-not $cycling) {
        $global:_ps10k_tab_cycle = $null
        try { $outcome = _ps10k_with_readline_input { _ps10k_grid_complete $line $cursor $Backward } }
        catch { $outcome = 'menu' }
    }
    if ($outcome -eq 'menu') {
        $fits = $true
        try { $fits = _ps10k_menu_fits $line $cursor } catch { }
        $outcome = if ($fits) { 'psreadline' } else { 'cycle' }
    }
    if ($outcome -eq 'cycle') {
        if ($Backward) { [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious($Key, $Arg) }
        else { [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($Key, $Arg) }
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        $global:_ps10k_tab_cycle = $line
    }
    elseif ($outcome -eq 'psreadline') {
        _ps10k_with_readline_input { [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete($Key, $Arg) }
    }
    # The completed line skipped syntax-highlighting's key handlers.
    if (${function:_ps10k_hl_refresh}) { _ps10k_hl_refresh $before }
}

if (Get-Module PSReadLine) {
    $global:_ps10k_tab_cycle = $null
    Set-PSReadLineKeyHandler -Key Tab -BriefDescription 'PS10kTabComplete' `
        -Description 'Completion grid, or cycle the matches in place when it does not fit' `
        -ScriptBlock { param($key, $arg) _ps10k_tab_complete $key $arg $false }
    Set-PSReadLineKeyHandler -Key Shift+Tab -BriefDescription 'PS10kTabCompleteBackward' `
        -Description 'Completion grid from the last match, or cycle backwards in place' `
        -ScriptBlock { param($key, $arg) _ps10k_tab_complete $key $arg $true }
    Add-PS10kHook -Type precmd -Action { $global:_ps10k_tab_cycle = $null }
}
