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

# Number of terminal columns a string occupies once escape sequences are removed.
function global:_ps10k_width([string]$Text) {
    $plain = _ps10k_strip_ansi $Text
    if (-not $plain) { return 0 }
    $width = 0
    $enum = [Globalization.StringInfo]::GetTextElementEnumerator($plain)
    while ($enum.MoveNext()) {
        $element = $enum.GetTextElement()
        $cp = 0
        try { $cp = [char]::ConvertToUtf32($element, 0) } catch { $cp = [int]$element[0] }
        if ($cp -lt 32) { continue }
        if (_ps10k_is_wide $cp) { $width += 2 } else { $width += 1 }
    }
    $width
}
