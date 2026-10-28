# syntax-highlighting plugin: zsh-syntax-highlighting for PSReadLine.
#   - while you type, the command turns green when it exists and red when it
#     does not (cmdlets, functions, aliases, scripts and executables, by name
#     or path: .ps1 and every extension in PATHEXT such as .exe, .bat, .cmd)
#   - strings, variables, parameters, operators and comments get their own colors
#   - parse errors (unclosed quotes, braces, ...) are shown in red
# Load it after autosuggestions so history navigation and completion are
# re-highlighted too.

if (-not (Get-Module PSReadLine)) { return }

$global:PS10K_HL = @{
    Valid   = "$([char]27)[38;5;76m"
    Invalid = "$([char]27)[38;5;196m"
    Current = $null
    Cache   = @{}
}

$ps10kE = [char]27
Set-PSReadLineOption -Colors @{
    Command   = $global:PS10K_HL.Valid
    Parameter = "$ps10kE[38;5;117m"
    Operator  = "$ps10kE[38;5;250m"
    Variable  = "$ps10kE[38;5;81m"
    String    = "$ps10kE[38;5;179m"
    Number    = "$ps10kE[38;5;141m"
    Type      = "$ps10kE[38;5;37m"
    Comment   = "$ps10kE[38;5;244m"
    Keyword   = "$ps10kE[38;5;170m"
    Member    = "$ps10kE[38;5;117m"
    Error     = "$ps10kE[38;5;196m"
    Emphasis  = "$ps10kE[38;5;214m"
    Default   = "$ps10kE[38;5;252m"
}
Remove-Variable -Name ps10kE -ErrorAction SilentlyContinue

# Get-Command also reports documents (.\notes.md opens in its app) as
# applications; only files Windows executes count.
function global:_ps10k_hl_executable($Command) {
    if ($Command.CommandType -ne 'Application') { return $true }
    $extensions = @(($env:PATHEXT -split ';') | Where-Object { $_ })
    if (-not $extensions) { $extensions = '.com', '.exe', '.bat', '.cmd' }
    $extensions -contains [IO.Path]::GetExtension($Command.Source)
}

function global:_ps10k_hl_command_valid([string]$Name) {
    $cache = $global:PS10K_HL.Cache
    if ($cache.ContainsKey($Name)) { return $cache[$Name] }
    # Resolves names and paths (.\build.bat, C:\tools\x.exe, .\script) alike.
    # Ignore, not SilentlyContinue: every partial word would land in $Error.
    $commands = @(Get-Command -Name $Name -ErrorAction Ignore)
    $valid = @($commands | Where-Object { _ps10k_hl_executable $_ }).Count -gt 0
    $cache[$Name] = $valid
    $valid
}

# True when every command name in $Line resolves.
function global:_ps10k_hl_line_valid([string]$Line) {
    if (-not $Line -or -not $Line.Trim()) { return $true }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    $commands = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        if ($name -and -not (_ps10k_hl_command_valid $name)) { return $false }
    }
    $true
}

# Sets the Command color for $Line; returns $true when it changed.
function global:_ps10k_hl_update([string]$Line) {
    $color = if (_ps10k_hl_line_valid $Line) { $global:PS10K_HL.Valid } else { $global:PS10K_HL.Invalid }
    if ($color -eq $global:PS10K_HL.Current) { return $false }
    $global:PS10K_HL.Current = $color
    Set-PSReadLineOption -Colors @{ Command = $color }
    $true
}

# Recolors after keys that replace the line (history, paste, completion):
# replacing the buffer with itself re-renders it with the new color.
function global:_ps10k_hl_refresh {
    try {
        $b = _ps10k_hl_buffer
        if (_ps10k_hl_update $b.Line) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $b.Line.Length, $b.Line)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($b.Cursor)
        }
    }
    catch { }
}

function global:_ps10k_hl_buffer {
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    @{ Line = $line; Cursor = $cursor }
}

# Characters that can change a command name. The color is set before the key
# is applied so PSReadLine's own render already uses it.
$ps10kChars = @([char[]]'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') + @('-', '_', '.')
foreach ($ps10kChar in $ps10kChars) {
    Set-PSReadLineKeyHandler -Chord "$ps10kChar" -BriefDescription 'PS10kHighlightInsert' -ScriptBlock {
        param($key, $arg)
        try {
            $b = _ps10k_hl_buffer
            [void](_ps10k_hl_update $b.Line.Insert($b.Cursor, [string]$key.KeyChar))
        }
        catch { }
        [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
    }
}

Set-PSReadLineKeyHandler -Key Backspace -BriefDescription 'PS10kHighlightBackspace' -ScriptBlock {
    param($key, $arg)
    try {
        $b = _ps10k_hl_buffer
        if ($b.Cursor -gt 0) { [void](_ps10k_hl_update $b.Line.Remove($b.Cursor - 1, 1)) }
    }
    catch { }
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
}

Set-PSReadLineKeyHandler -Key Delete -BriefDescription 'PS10kHighlightDelete' -ScriptBlock {
    param($key, $arg)
    try {
        $b = _ps10k_hl_buffer
        if ($b.Cursor -lt $b.Line.Length) { [void](_ps10k_hl_update $b.Line.Remove($b.Cursor, 1)) }
    }
    catch { }
    [Microsoft.PowerShell.PSConsoleReadLine]::DeleteChar($key, $arg)
}

# Keys that replace the whole line (history, paste, completion): run the
# bound function, then recolor.
# powershell10k's own handlers (PS10k*, such as the autosuggestions Tab) call
# _ps10k_hl_refresh themselves.
foreach ($ps10kKey in 'UpArrow', 'DownArrow', 'Ctrl+v', 'Tab', 'Shift+Tab') {
    $ps10kBound = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq $ps10kKey } | Select-Object -First 1
    if (-not $ps10kBound -or $ps10kBound.Function -like 'PS10k*') { continue }
    $ps10kFunction = $ps10kBound.Function
    $ps10kHandler = [scriptblock]::Create(@"
param(`$key, `$arg)
_ps10k_with_ctrl_c_as_key { [Microsoft.PowerShell.PSConsoleReadLine]::$ps10kFunction(`$key, `$arg) }
_ps10k_hl_refresh
"@)
    Set-PSReadLineKeyHandler -Chord $ps10kKey -BriefDescription "PS10k$ps10kFunction" -ScriptBlock $ps10kHandler
}

# Completion grid colors, like ls colors: folders in the prompt's folder color,
# executables green, archives red. Set $PS10K_HL_COMPLETION = $false to turn
# it off.
$global:PS10K_HL.Archives = @('.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.tbz', '.tbz2', '.xz', '.txz',
    '.zst', '.tzst', '.lz', '.lzma', '.tlz', '.lz4', '.z', '.cab', '.jar', '.war', '.ear', '.deb', '.rpm', '.cpio',
    '.arj', '.lzh', '.lha', '.ace', '.wim', '.esd', '.nupkg', '.vsix', '.appx', '.msix')

# The folder segment's color: its background in rainbow style (white text on
# blue), its text color in the other styles.
function global:_ps10k_hl_folder_color {
    if (Get-Command _ps10k_segment_colors -ErrorAction Ignore) {
        $colors = _ps10k_segment_colors @{ Name = 'dir' }
        $color = if ($global:P10K.Style -eq 'rainbow' -and $null -ne $colors.Bg) { $colors.Bg } else { $colors.Fg }
        if ($null -ne $color) { return (_ps10k_fg $color) }
    }
    "$([char]27)[38;5;39m"
}

function global:_ps10k_hl_completion_color($Result, [string]$FolderColor) {
    if ($Result.ResultType -eq 'ProviderContainer') { return $FolderColor }
    if ($Result.ResultType -ne 'ProviderItem') { return $null }
    $extension = [IO.Path]::GetExtension($Result.ListItemText)
    if (-not $extension) { return $null }
    $executables = @(($env:PATHEXT -split ';') | Where-Object { $_ }) + '.ps1'
    if ($executables -contains $extension) { return $global:PS10K_HL.Valid }
    if ($global:PS10K_HL.Archives -contains $extension) { return $global:PS10K_HL.Invalid }
    $null
}

# Colors ListItemText, which PSReadLine only displays (its width math skips
# escape codes). Only the foreground is reset, so the selected entry keeps its
# Selection background.
function global:_ps10k_hl_color_completions($Completion) {
    if ($global:PS10K_HL_COMPLETION -eq $false) { return }
    $results = $Completion.CompletionMatches
    if (-not $results -or $results.Count -lt 2) { return }
    # Without a common CompletionText prefix PSReadLine takes the prefix from
    # ListItemText, which would then contain the color codes.
    $prefix = $results[0].CompletionText
    foreach ($r in $results) {
        $i = 0
        while ($i -lt $prefix.Length -and $i -lt $r.CompletionText.Length -and
            [char]::ToLowerInvariant($prefix[$i]) -eq [char]::ToLowerInvariant($r.CompletionText[$i])) { $i++ }
        $prefix = $prefix.Substring(0, $i)
        if (-not $prefix) { return }
    }
    $folderColor = _ps10k_hl_folder_color
    $esc = [char]27
    for ($n = 0; $n -lt $results.Count; $n++) {
        $r = $results[$n]
        $color = _ps10k_hl_completion_color $r $folderColor
        if (-not $color -or $r.ListItemText.Contains($esc)) { continue }
        $toolTip = if ($r.ToolTip) { $r.ToolTip } else { $r.ListItemText }
        $results[$n] = New-Object System.Management.Automation.CompletionResult(
            $r.CompletionText, "$color$($r.ListItemText)$esc[39m", $r.ResultType, $toolTip)
    }
}

# PSReadLine gets its completions from TabExpansion2, so wrapping it colors
# both the menu and in-place cycling (which only uses CompletionText).
if (-not $global:_ps10k_tabexpansion2) {
    $global:_ps10k_tabexpansion2 = (Get-Command TabExpansion2 -CommandType Function -ErrorAction Ignore).ScriptBlock
}
if ($global:_ps10k_tabexpansion2) {
    function global:TabExpansion2 {
        [CmdletBinding(DefaultParameterSetName = 'ScriptInputSet')]
        param(
            [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory = $true, Position = 0)]
            [string]$inputScript,
            [Parameter(ParameterSetName = 'ScriptInputSet', Position = 1)]
            [int]$cursorColumn = $inputScript.Length,
            [Parameter(ParameterSetName = 'AstInputSet', Mandatory = $true, Position = 0)]
            [System.Management.Automation.Language.Ast]$ast,
            [Parameter(ParameterSetName = 'AstInputSet', Mandatory = $true, Position = 1)]
            [System.Management.Automation.Language.Token[]]$tokens,
            [Parameter(ParameterSetName = 'AstInputSet', Mandatory = $true, Position = 2)]
            [System.Management.Automation.Language.IScriptPosition]$positionOfCursor,
            [Parameter(ParameterSetName = 'ScriptInputSet', Position = 2)]
            [Parameter(ParameterSetName = 'AstInputSet', Position = 3)]
            [Hashtable]$options = $null
        )
        if ($PSCmdlet.ParameterSetName -eq 'ScriptInputSet') { $PSBoundParameters['cursorColumn'] = $cursorColumn }
        $completion = & $global:_ps10k_tabexpansion2 @PSBoundParameters
        try { _ps10k_hl_color_completions $completion } catch { }
        $completion
    }
}

# A fresh prompt starts with an empty line; commands may have been defined.
Add-PS10kHook -Type precmd -Action {
    $global:PS10K_HL.Cache = @{}
    [void](_ps10k_hl_update '')
}

Remove-Variable -Name ps10kChars, ps10kChar, ps10kKey, ps10kBound, ps10kFunction, ps10kHandler -ErrorAction SilentlyContinue
