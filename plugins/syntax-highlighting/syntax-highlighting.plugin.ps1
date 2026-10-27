# syntax-highlighting plugin: zsh-syntax-highlighting for PSReadLine.
#   - while you type, the command turns green when it exists and red when it
#     does not (cmdlets, functions, aliases, executables and script paths)
#   - strings, variables, parameters, operators and comments get their own colors
#   - parse errors (unclosed quotes, braces, ...) are shown in red
# Load it after autosuggestions so history navigation is re-highlighted too.

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

function global:_ps10k_hl_command_valid([string]$Name) {
    $cache = $global:PS10K_HL.Cache
    if ($cache.ContainsKey($Name)) { return $cache[$Name] }
    $valid = $false
    if ($Name -match '[\\/]' -or $Name.StartsWith('.')) {
        $valid = Test-Path -LiteralPath $Name -PathType Leaf -ErrorAction SilentlyContinue
    }
    if (-not $valid) { $valid = [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1) }
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

# Keys that replace the whole line (history, paste): run the bound function,
# then re-render with the right color by replacing the buffer with itself.
foreach ($ps10kKey in 'UpArrow', 'DownArrow', 'Ctrl+v') {
    $ps10kBound = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq $ps10kKey } | Select-Object -First 1
    if (-not $ps10kBound -or $ps10kBound.Function -like 'PS10k*') { continue }
    $ps10kFunction = $ps10kBound.Function
    $ps10kHandler = [scriptblock]::Create(@"
param(`$key, `$arg)
[Microsoft.PowerShell.PSConsoleReadLine]::$ps10kFunction(`$key, `$arg)
try {
    `$b = _ps10k_hl_buffer
    if (_ps10k_hl_update `$b.Line) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, `$b.Line.Length, `$b.Line)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(`$b.Cursor)
    }
}
catch { }
"@)
    Set-PSReadLineKeyHandler -Chord $ps10kKey -BriefDescription "PS10k$ps10kFunction" -ScriptBlock $ps10kHandler
}

# A fresh prompt starts with an empty line; commands may have been defined.
Add-PS10kHook -Type precmd -Action {
    $global:PS10K_HL.Cache = @{}
    [void](_ps10k_hl_update '')
}

Remove-Variable -Name ps10kChars, ps10kChar, ps10kKey, ps10kBound, ps10kFunction, ps10kHandler -ErrorAction SilentlyContinue
