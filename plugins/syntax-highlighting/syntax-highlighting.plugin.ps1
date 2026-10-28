# syntax-highlighting plugin: zsh-syntax-highlighting for PSReadLine.
#   - while you type, the command turns green when it exists and red when it
#     does not (cmdlets, functions, aliases, scripts and executables, by name
#     or path: .ps1 and every extension in PATHEXT such as .exe, .bat, .cmd)
#   - strings, variables, parameters, operators and comments get their own colors
#   - parse errors (unclosed quotes, braces, ...) are shown in red
#   - arguments are underlined while they are existing paths or the start of
#     one (ls Wo, ls Workspace\Docker\), like zsh's path highlighting
# Load it after autosuggestions so history navigation and completion are
# re-highlighted too.

if (-not (Get-Module PSReadLine)) { return }

$global:PS10K_HL = @{
    # The color scheme's green and red, so they follow the terminal theme.
    Valid   = "$([char]27)[32m"
    Invalid = "$([char]27)[31m"
    # Default and String use the terminal's own colors (default foreground,
    # the scheme's magenta/purple), so they follow the color scheme.
    Default = "$([char]27)[39m"
    String  = "$([char]27)[35m"
    Current = $null
    Cache   = @{}
}

$ps10kE = [char]27
# PSReadLine colors whitespace with a plain color reset that leaves underline
# on, so every color but the underlined ones starts with "underline off".
# Selection is the menu highlight: terminal foreground as background,
# terminal background as text.
Set-PSReadLineOption -Colors @{
    Command   = "$ps10kE[24m" + $global:PS10K_HL.Valid
    Parameter = "$ps10kE[24;38;5;117m"
    Operator  = "$ps10kE[24;38;5;250m"
    Variable  = "$ps10kE[24;38;5;81m"
    String    = "$ps10kE[24m" + $global:PS10K_HL.String
    Number    = "$ps10kE[24;38;5;141m"
    Type      = "$ps10kE[24;38;5;37m"
    Comment   = "$ps10kE[24;38;5;244m"
    Keyword   = "$ps10kE[24;38;5;170m"
    Member    = "$ps10kE[24;38;5;117m"
    Error     = "$ps10kE[24;38;5;196m"
    Emphasis  = "$ps10kE[24;38;5;214m"
    Default   = "$ps10kE[24m" + $global:PS10K_HL.Default
    Selection = "$ps10kE[7m"
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
function global:_ps10k_hl_line_valid([string]$Line) { (_ps10k_hl_analyze $Line).Valid }

# True when $Value is an existing file or folder, or the start of the name of
# one (Wo for Workspace). A trailing separator needs an existing folder.
function global:_ps10k_hl_path_like([string]$Value) {
    if (-not $Value -or $Value.IndexOfAny([char[]]'*?') -ge 0) { return $false }
    $location = $executionContext.SessionState.Path.CurrentLocation
    $key = "path:$($location.Path)|$Value"
    $cache = $global:PS10K_HL.Cache
    if ($cache.ContainsKey($key)) { return $cache[$key] }
    $result = $false
    try {
        $full = $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Value)
        if ($Value.EndsWith('\') -or $Value.EndsWith('/')) { $result = [IO.Directory]::Exists($full) }
        elseif ([IO.File]::Exists($full) -or [IO.Directory]::Exists($full)) { $result = $true }
        else {
            $parent = [IO.Path]::GetDirectoryName($full)
            $leaf = [IO.Path]::GetFileName($full)
            if ($parent -and $leaf -and [IO.Directory]::Exists($parent)) {
                $result = [IO.Directory]::EnumerateFileSystemEntries($parent, "$leaf*").GetEnumerator().MoveNext()
            }
        }
    }
    catch { $result = $false }
    $cache[$key] = $result
    $result
}

# Whether the line's commands resolve, and whether all its plain (Bare) and
# quoted (Quoted) arguments are paths. PSReadLine has one color per token
# kind, not per word, so plain arguments are underlined together, and only
# when all of them are paths: nothing is ever underlined that is not a path.
function global:_ps10k_hl_analyze([string]$Line) {
    $state = @{ Valid = $true; Bare = $false; Quoted = $false }
    if (-not $Line -or -not $Line.Trim()) { return $state }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    $bare = New-Object System.Collections.ArrayList
    $quoted = New-Object System.Collections.ArrayList
    foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $command.GetCommandName()
        if ($name -and -not (_ps10k_hl_command_valid $name)) { $state.Valid = $false }
        foreach ($element in @($command.CommandElements | Select-Object -Skip 1)) {
            if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
            if ($element.StringConstantType -eq 'BareWord') { [void]$bare.Add($element.Value) }
            else { [void]$quoted.Add($element.Value) }
        }
    }
    $state.Bare = $bare.Count -gt 0 -and @($bare | Where-Object { -not (_ps10k_hl_path_like $_) }).Count -eq 0
    $state.Quoted = $quoted.Count -gt 0 -and @($quoted | Where-Object { -not (_ps10k_hl_path_like $_) }).Count -eq 0
    $state
}

# Sets the Command, Default and String colors for $Line; returns $true when
# they changed.
function global:_ps10k_hl_update([string]$Line) {
    $state = _ps10k_hl_analyze $Line
    _ps10k_hl_apply $state.Valid $state.Bare $state.Quoted
}

function global:_ps10k_hl_apply([bool]$Valid, [bool]$Bare, [bool]$Quoted) {
    $hl = $global:PS10K_HL
    $command = if ($Valid) { $hl.Valid } else { $hl.Invalid }
    $key = "$command|$Bare|$Quoted"
    $hl.LastValid = $Valid
    if ($key -eq $hl.Current) { return $false }
    $hl.Current = $key
    $esc = [char]27
    Set-PSReadLineOption -Colors @{
        Command = "$esc[24m" + $command
        Default = $(if ($Bare) { "$esc[4m" } else { "$esc[24m" }) + $hl.Default
        String  = $(if ($Quoted) { "$esc[4m" } else { "$esc[24m" }) + $hl.String
    }
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
# Enter renders the line once more before running it: without the underline,
# so it cannot carry over into the command's output.
Add-PS10kHook -Type preexec -Action { [void](_ps10k_hl_apply ([bool]$global:PS10K_HL.LastValid) $false $false) }
_ps10k_bind_accept_line

Remove-Variable -Name ps10kChars, ps10kChar, ps10kKey, ps10kBound, ps10kFunction, ps10kHandler -ErrorAction SilentlyContinue
