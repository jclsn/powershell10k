# Glyph sets. 'nerdfont' needs a Nerd Font such as JetBrainsMono Nerd Font (installed by
# install.ps1), 'unicode' works with any modern font, 'ascii' works everywhere.

$global:PS10K_ICON_SETS = @{
    nerdfont = @{
        os = (_ps10k_u 0xF17A); home = (_ps10k_u 0xF015); folder = (_ps10k_u 0xF07C)
        lock = (_ps10k_u 0xF023); branch = (_ps10k_u 0xF126); ok = (_ps10k_u 0xF00C)
        fail = (_ps10k_u 0xF00D); time = (_ps10k_u 0xF017); exec = (_ps10k_u 0xF252)
        jobs = (_ps10k_u 0xF013); python = (_ps10k_u 0xE73C); node = (_ps10k_u 0xE718)
        dotnet = (_ps10k_u 0xE77F); aws = (_ps10k_u 0xF270); user = (_ps10k_u 0xF007)
        admin = (_ps10k_u 0xF0E7); remote = (_ps10k_u 0xF489)
        prompt = (_ps10k_u 0x276F); prompt_vicmd = (_ps10k_u 0x276E); ahead = (_ps10k_u 0x21E1); behind = (_ps10k_u 0x21E3)
        ellipsis = (_ps10k_u 0x2026)
    }
    unicode = @{
        os = ''; home = ''; folder = ''; lock = ''; branch = ''
        ok = (_ps10k_u 0x2714); fail = (_ps10k_u 0x2718); time = ''; exec = ''
        jobs = (_ps10k_u 0x2699); python = ''; node = ''; dotnet = ''; aws = ''
        user = ''; admin = (_ps10k_u 0x26A1); remote = ''
        prompt = (_ps10k_u 0x276F); prompt_vicmd = (_ps10k_u 0x276E); ahead = (_ps10k_u 0x21E1); behind = (_ps10k_u 0x21E3)
        ellipsis = (_ps10k_u 0x2026)
    }
    ascii = @{
        os = ''; home = ''; folder = ''; lock = ''; branch = ''
        ok = 'ok'; fail = 'x'; time = ''; exec = ''; jobs = '%'
        python = 'py'; node = 'node'; dotnet = '.net'; aws = 'aws'
        user = ''; admin = '#'; remote = ''
        prompt = '>'; prompt_vicmd = '<'; ahead = '>'; behind = '<'; ellipsis = '..'
    }
}

# Powerline separators per head shape: L/R are solid, SubL/SubR are thin.
$global:PS10K_SEPARATORS = @{
    sharp   = @{ L = (_ps10k_u 0xE0B0); R = (_ps10k_u 0xE0B2); SubL = (_ps10k_u 0xE0B1); SubR = (_ps10k_u 0xE0B3) }
    round   = @{ L = (_ps10k_u 0xE0B4); R = (_ps10k_u 0xE0B6); SubL = (_ps10k_u 0xE0B5); SubR = (_ps10k_u 0xE0B7) }
    slanted = @{ L = (_ps10k_u 0xE0BC); R = (_ps10k_u 0xE0BA); SubL = (_ps10k_u 0xE0BD); SubR = (_ps10k_u 0xE0BB) }
    flat    = @{ L = ''; R = ''; SubL = '|'; SubR = '|' }
}

# Frame and gap glyphs for two-line prompts.
$global:PS10K_FRAME = @{
    unicode = @{ Top = (_ps10k_u 0x256D) + (_ps10k_u 0x2500); Bottom = (_ps10k_u 0x2570) + (_ps10k_u 0x2500) }
    ascii   = @{ Top = '+-'; Bottom = '+-' }
}
$global:PS10K_GAPS = @{
    none = @{ unicode = ' '; ascii = ' ' }
    dot  = @{ unicode = (_ps10k_u 0x00B7); ascii = '.' }
    line = @{ unicode = (_ps10k_u 0x2500); ascii = '-' }
}

function global:_ps10k_icon([string]$Name) {
    if (-not $Name) { return '' }
    $cfg = $global:P10K
    if ($cfg -and $cfg.Icons -and $cfg.Icons.Contains($Name)) { return [string]$cfg.Icons[$Name] }
    $mode = if ($cfg -and $cfg.Mode) { $cfg.Mode } else { 'nerdfont' }
    $set = $global:PS10K_ICON_SETS[$mode]
    if (-not $set) { $set = $global:PS10K_ICON_SETS['nerdfont'] }
    if ($set.ContainsKey($Name)) { return $set[$Name] }
    ''
}

function global:_ps10k_separators {
    $cfg = $global:P10K
    if ($cfg.Mode -ne 'nerdfont') { return $global:PS10K_SEPARATORS['flat'] }
    $sep = $global:PS10K_SEPARATORS[$cfg.Heads]
    if (-not $sep) { $sep = $global:PS10K_SEPARATORS['sharp'] }
    $sep
}

function global:_ps10k_glyph_class {
    if ($global:P10K.Mode -eq 'ascii') { 'ascii' } else { 'unicode' }
}
