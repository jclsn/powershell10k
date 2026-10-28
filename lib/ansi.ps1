# ANSI escape sequences and display-width helpers.
# Files in this project are kept ASCII-only so Windows PowerShell 5.1 parses
# them correctly without a BOM; non-ASCII glyphs are built from code points.

$global:PS10K_ESC = [string][char]27
$global:PS10K_RESET = "$($global:PS10K_ESC)[0m"
$global:PS10K_BOLD = "$($global:PS10K_ESC)[1m"
$global:PS10K_NOBOLD = "$($global:PS10K_ESC)[22m"

$global:PS10K_COLOR_NAMES = @{
    black = 0; red = 1; green = 2; yellow = 3; blue = 4; magenta = 5; cyan = 6; white = 7
    grey = 8; gray = 8; brightred = 9; brightgreen = 10; brightyellow = 11
    brightblue = 12; brightmagenta = 13; brightcyan = 14; brightwhite = 15
}

# Returns the SGR sequence for a color: 0-255, a name, or '#rrggbb'.
function global:_ps10k_color {
    param([object]$Color, [switch]$Background)
    if ($null -eq $Color) { return '' }
    $value = "$Color".Trim().ToLowerInvariant()
    if ($value -eq '') { return '' }
    $base = if ($Background) { '48' } else { '38' }
    if ($global:PS10K_COLOR_NAMES.ContainsKey($value)) { $value = "$($global:PS10K_COLOR_NAMES[$value])" }
    if ($value -match '^\d{1,3}$') {
        return "$($global:PS10K_ESC)[$base;5;$([int]$value)m"
    }
    if ($value -match '^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$') {
        $r = [Convert]::ToInt32($Matches[1], 16)
        $g = [Convert]::ToInt32($Matches[2], 16)
        $b = [Convert]::ToInt32($Matches[3], 16)
        return "$($global:PS10K_ESC)[$base;2;$r;$g;$($b)m"
    }
    return ''
}

function global:_ps10k_fg([object]$Color) { _ps10k_color -Color $Color }
function global:_ps10k_bg([object]$Color) { _ps10k_color -Color $Color -Background }

function global:_ps10k_u([int]$CodePoint) { [char]::ConvertFromUtf32($CodePoint) }

$global:PS10K_ANSI_PATTERN = "$([char]27)(\[[0-9;?]*[ -/]*[@-~]|\][^$([char]7)$([char]27)]*($([char]7)|$([char]27)\\)|[78])"

function global:_ps10k_strip_ansi([string]$Text) {
    if (-not $Text) { return '' }
    $Text -replace $global:PS10K_ANSI_PATTERN, ''
}

function global:_ps10k_is_wide([int]$cp) {
    ($cp -ge 0x1100 -and $cp -le 0x115F) -or
    ($cp -ge 0x2E80 -and $cp -le 0xA4CF) -or
    ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
    ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
    ($cp -ge 0xFE30 -and $cp -le 0xFE4F) -or
    ($cp -ge 0xFF00 -and $cp -le 0xFF60) -or
    ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
    ($cp -ge 0x1F300 -and $cp -le 0x1F64F) -or
    ($cp -ge 0x1F900 -and $cp -le 0x1F9FF) -or
    ($cp -ge 0x20000 -and $cp -le 0x3FFFD)
}

# The ranges of _ps10k_is_wide as UTF-16, so whole strings can be counted at
# once (astral ranges as surrogate pairs).
$global:PS10K_WIDE_PATTERN = ('[{0}u1100-{0}u115F{0}u2E80-{0}uA4CF{0}uAC00-{0}uD7A3{0}uF900-{0}uFAFF{0}uFE30-{0}uFE4F{0}uFF00-{0}uFF60{0}uFFE0-{0}uFFE6]' +
    '|{0}uD83C[{0}uDF00-{0}uDFFF]|{0}uD83D[{0}uDC00-{0}uDE4F]|{0}uD83E[{0}uDD00-{0}uDDFF]|[{0}uD840-{0}uD8BF][{0}uDC00-{0}uDFFF]') -f [char]92

# Number of terminal columns a string occupies once escape sequences are
# removed. Hot path (prompt, completion grid): plain ASCII returns at once,
# everything else is counted with regexes rather than per character.
function global:_ps10k_width([string]$Text) {
    if (-not $Text) { return 0 }
    if ($Text.IndexOf([char]27) -ge 0) { $Text = $Text -replace $global:PS10K_ANSI_PATTERN, '' }
    if ($Text -cmatch '^[\x20-\x7E]*$') { return $Text.Length }
    $elements = (New-Object Globalization.StringInfo $Text).LengthInTextElements
    $controls = [regex]::Matches($Text, '[\x00-\x1F]').Count
    $elements - $controls + [regex]::Matches($Text, $global:PS10K_WIDE_PATTERN).Count
}
