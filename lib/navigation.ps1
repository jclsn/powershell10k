# zsh-style navigation:
#   cd             without arguments goes to your home folder, wherever you are
#                  (Windows PowerShell 5.1 does nothing, and on other drives
#                  such as HKCU: `cd ~` would mean that provider's home)
#   ... and more   ... is ..\.., .... is ..\..\.. and so on, also at the start
#                  of a path (...\src). The aliases plugin expands them in the
#                  command line on Enter and Tab; cd understands them itself.

# Expands one dotted path; anything else is returned unchanged. The separator
# follows the one typed (.../src becomes ../../src).
function global:_ps10k_expand_dots([string]$Path) {
    if ($Path -notmatch '^(\.{3,})([\\/].*)?$') { return $Path }
    $rest = $Matches[2]
    $separator = if ($rest -and $rest[0] -eq '/') { '/' } else { '\' }
    ((@('..') * ($Matches[1].Length - 1)) -join $separator) + $rest
}

# Expands the dotted paths among a command line's plain arguments. Command
# names (the ... command itself) and quoted text are left alone.
function global:_ps10k_expand_dots_line([string]$Line) {
    if (-not $Line -or $Line.IndexOf('...') -lt 0) { return $Line }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    $words = @(foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        foreach ($element in @($command.CommandElements | Select-Object -Skip 1)) {
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $element.StringConstantType -eq 'BareWord' -and $element.Value -match '^\.{3,}') { $element }
        }
    })
    # From the end, so earlier offsets stay valid.
    foreach ($word in @($words | Sort-Object { $_.Extent.StartOffset } -Descending)) {
        $start = $word.Extent.StartOffset
        $Line = $Line.Substring(0, $start) + (_ps10k_expand_dots $word.Extent.Text) + $Line.Substring($word.Extent.EndOffset)
    }
    $Line
}

function global:_ps10k_cd {
    if ($args.Count -eq 0) { Set-Location -LiteralPath $HOME; return }
    # Only dotted entries are replaced, in place: -Path and the like are
    # marked as parameter names in $args, and a copy or new string loses that.
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -isnot [string]) { continue }
        $expanded = _ps10k_expand_dots $args[$i]
        if ($expanded -ne $args[$i]) { $args[$i] = $expanded }
    }
    Set-Location @args
}

_ps10k_set_alias cd _ps10k_cd
