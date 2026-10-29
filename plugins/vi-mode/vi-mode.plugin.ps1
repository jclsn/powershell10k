# vi-mode plugin: vi key bindings, like `bindkey -v` and oh-my-zsh's vi-mode.
#   Esc            command mode; i, a, I, A, ... back to insert mode
#   cursor         blinking bar in insert mode, block in command mode
#   prompt char    points back in command mode (powerlevel10k theme)
#   Up/Down, k/j   history search for lines starting with what you typed
#   Ctrl+p/n       the same in insert mode
#   Ctrl+r/s       incremental history search in both modes
#   Ctrl+w         delete the word before the cursor in insert mode
#   v              edit the line in $env:VISUAL / $env:EDITOR (command mode)
# Settings, set them in your profile before powershell10k is loaded:
#   $PS10K_VI_CURSOR = $false     leave the cursor shape alone
#   $PS10K_VI_CURSOR_INSERT = 5   cursor shapes: 1/2 block, 3/4 underline,
#   $PS10K_VI_CURSOR_NORMAL = 2   5/6 bar; odd numbers blink
# The loader runs this plugin first because switching PSReadLine to vi mode
# resets every key binding. The mode-dependent cursor and prompt char need
# PSReadLine 2.1+; with 2.0 PSReadLine changes the cursor size itself.

if (-not (Get-Module PSReadLine)) { return }

if ($null -eq $global:PS10K_VI_CURSOR) { $global:PS10K_VI_CURSOR = $true }
if ($null -eq $global:PS10K_VI_CURSOR_INSERT) { $global:PS10K_VI_CURSOR_INSERT = 5 }
if ($null -eq $global:PS10K_VI_CURSOR_NORMAL) { $global:PS10K_VI_CURSOR_NORMAL = 2 }
$global:PS10K_VI_MODE = 'Insert'

Set-PSReadLineOption -EditMode Vi

# Sets the cursor shape for 'Insert' or 'Command'; anything else restores the
# terminal's default shape.
function global:_ps10k_vi_cursor([string]$Mode) {
    if (-not $global:PS10K_VI_CURSOR) { return }
    $shape = switch ($Mode) {
        'Insert' { $global:PS10K_VI_CURSOR_INSERT }
        'Command' { $global:PS10K_VI_CURSOR_NORMAL }
        default { 0 }
    }
    [Console]::Write("$([char]27)[$([int]$shape) q")
}

# Runs on every prompt; Set-PSReadLineOption only when the text changes.
function global:_ps10k_vi_prompt_text([string]$Mode) {
    $icon = if ($Mode -eq 'Command') { 'prompt_vicmd' } else { 'prompt' }
    $text = (_ps10k_icon $icon) + ' '
    if (((Get-PSReadLineOption).PromptText -join '') -eq $text) { return }
    try { Set-PSReadLineOption -PromptText $text } catch { }
}

function global:_ps10k_vi_mode_changed($Mode) {
    $mode = "$Mode"
    _ps10k_vi_cursor $mode
    if ($global:PS10K_VI_MODE -eq $mode) { return }
    $global:PS10K_VI_MODE = $mode
    # Command mode edits (x, dd, u, p, ...) bypass syntax-highlighting's key
    # handlers, so the command color is refreshed on every mode switch.
    $recolor = $false
    $highlight = [bool]${function:_ps10k_hl_update}
    # The line as the highlighter last saw it: cw, cc, C and similar shorten it
    # without passing through a wrappable key handler.
    $previous = if ($highlight) { $global:PS10K_HL.LastLine } else { $null }
    if ($highlight) {
        try { $b = _ps10k_hl_buffer; $recolor = _ps10k_hl_update $b.Line } catch { }
    }
    $state = $global:_ps10k_state
    if ($state) { $state.ViMode = $mode }
    if ($state -and $state.LastPrompt) {
        # Redraws the cached prompt with the other prompt char (and the buffer).
        _ps10k_vi_prompt_text $mode
        $state.ViRedraw = $true
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
    elseif ($recolor) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $b.Line.Length, $b.Line)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($b.Cursor)
    }
    if ($highlight) { _ps10k_hl_clear_padding $previous }
}

if ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
    Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler { param($mode) _ps10k_vi_mode_changed $mode }
}
else {
    Set-PSReadLineOption -ViModeIndicator Cursor
}

foreach ($ps10kViMode in 'Insert', 'Command') {
    Set-PSReadLineKeyHandler -ViMode $ps10kViMode -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -ViMode $ps10kViMode -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -ViMode $ps10kViMode -Key Ctrl+r -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -ViMode $ps10kViMode -Key Ctrl+s -Function ForwardSearchHistory
}
Set-PSReadLineKeyHandler -ViMode Command -Key k -Function HistorySearchBackward
Set-PSReadLineKeyHandler -ViMode Command -Key j -Function HistorySearchForward
Set-PSReadLineKeyHandler -ViMode Insert -Key Ctrl+p -Function HistorySearchBackward
Set-PSReadLineKeyHandler -ViMode Insert -Key Ctrl+n -Function HistorySearchForward
Set-PSReadLineKeyHandler -ViMode Insert -Key Ctrl+w -Function UnixWordRubout

# Every line starts in insert mode; programs get the default cursor back.
Add-PS10kHook -Type precmd -Action {
    $global:PS10K_VI_MODE = 'Insert'
    _ps10k_vi_prompt_text 'Insert'
    _ps10k_vi_cursor 'Insert'
}
Add-PS10kHook -Type preexec -Action { _ps10k_vi_cursor 'Default' }
_ps10k_bind_accept_line

Remove-Variable -Name ps10kViMode -ErrorAction SilentlyContinue
