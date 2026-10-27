# Prompt rendering for the four styles: rainbow, classic, lean and pure.
# Colors are xterm-256 indexes, looked up by "segment_state" then "segment".

$global:PS10K_PALETTES = @{
    rainbow = @{
        os_icon = @{ Fg = 232; Bg = 7 }
        dir = @{ Fg = 254; Bg = 4 }
        git_clean = @{ Fg = 0; Bg = 2 }; git_untracked = @{ Fg = 0; Bg = 2 }
        git_modified = @{ Fg = 0; Bg = 3 }; git_conflicted = @{ Fg = 0; Bg = 1 }
        status_ok = @{ Fg = 2; Bg = 0 }; status_error = @{ Fg = 3; Bg = 1 }
        command_execution_time = @{ Fg = 0; Bg = 3 }
        background_jobs = @{ Fg = 6; Bg = 0 }
        virtualenv = @{ Fg = 0; Bg = 4 }; anaconda = @{ Fg = 0; Bg = 4 }
        node_version = @{ Fg = 7; Bg = 2 }; dotnet_version = @{ Fg = 7; Bg = 5 }
        aws = @{ Fg = 0; Bg = 208 }
        context = @{ Fg = 180; Bg = 0 }; context_admin = @{ Fg = 178; Bg = 0 }
        time = @{ Fg = 0; Bg = 7 }
        default = @{ Fg = 7; Bg = 238 }
        prompt_ok = @{ Fg = 76 }; prompt_error = @{ Fg = 196 }
        frame = @{ Fg = 242 }; gap = @{ Fg = 242 }; subsep = @{ Fg = 244 }
    }
    classic = @{
        os_icon = @{ Fg = 255 }; dir = @{ Fg = 31 }
        git_clean = @{ Fg = 76 }; git_untracked = @{ Fg = 76 }
        git_modified = @{ Fg = 178 }; git_conflicted = @{ Fg = 196 }
        status_ok = @{ Fg = 70 }; status_error = @{ Fg = 160 }
        command_execution_time = @{ Fg = 248 }; background_jobs = @{ Fg = 37 }
        virtualenv = @{ Fg = 37 }; anaconda = @{ Fg = 37 }
        node_version = @{ Fg = 70 }; dotnet_version = @{ Fg = 134 }; aws = @{ Fg = 208 }
        context = @{ Fg = 180 }; context_admin = @{ Fg = 178 }
        time = @{ Fg = 66 }
        default = @{ Fg = 250 }
        prompt_ok = @{ Fg = 76 }; prompt_error = @{ Fg = 196 }
        frame = @{ Fg = 240 }; gap = @{ Fg = 240 }; subsep = @{ Fg = 242 }
        background = 236
    }
    lean = @{
        os_icon = @{ Fg = 255 }; dir = @{ Fg = 31 }
        git_clean = @{ Fg = 76 }; git_untracked = @{ Fg = 39 }
        git_modified = @{ Fg = 178 }; git_conflicted = @{ Fg = 196 }
        status_ok = @{ Fg = 70 }; status_error = @{ Fg = 160 }
        command_execution_time = @{ Fg = 101 }; background_jobs = @{ Fg = 70 }
        virtualenv = @{ Fg = 37 }; anaconda = @{ Fg = 37 }
        node_version = @{ Fg = 70 }; dotnet_version = @{ Fg = 134 }; aws = @{ Fg = 208 }
        context = @{ Fg = 180 }; context_admin = @{ Fg = 178 }
        time = @{ Fg = 66 }
        default = @{ Fg = 250 }
        prompt_ok = @{ Fg = 76 }; prompt_error = @{ Fg = 196 }
        frame = @{ Fg = 242 }; gap = @{ Fg = 242 }; subsep = @{ Fg = 242 }
    }
    pure = @{
        os_icon = @{ Fg = 8 }; dir = @{ Fg = 4 }
        git_clean = @{ Fg = 8 }; git_untracked = @{ Fg = 8 }
        git_modified = @{ Fg = 8 }; git_conflicted = @{ Fg = 1 }
        status_ok = @{ Fg = 2 }; status_error = @{ Fg = 1 }
        command_execution_time = @{ Fg = 3 }; background_jobs = @{ Fg = 8 }
        virtualenv = @{ Fg = 8 }; anaconda = @{ Fg = 8 }
        node_version = @{ Fg = 8 }; dotnet_version = @{ Fg = 8 }; aws = @{ Fg = 8 }
        context = @{ Fg = 8 }; context_admin = @{ Fg = 3 }
        time = @{ Fg = 8 }
        default = @{ Fg = 8 }
        prompt_ok = @{ Fg = 5 }; prompt_error = @{ Fg = 1 }
        frame = @{ Fg = 8 }; gap = @{ Fg = 8 }; subsep = @{ Fg = 8 }
    }
}

function global:_ps10k_palette {
    $p = $global:PS10K_PALETTES[$global:P10K.Style]
    if (-not $p) { $p = $global:PS10K_PALETTES['rainbow'] }
    $p
}

# Resolves @{ Fg; Bg } for a segment result, applying user overrides.
function global:_ps10k_segment_colors($Segment) {
    $cfg = $global:P10K
    $palette = _ps10k_palette
    $keys = @()
    if ($Segment.State) { $keys += "$($Segment.Name)_$($Segment.State)" }
    $keys += "$($Segment.Name)"

    $colors = $null
    foreach ($key in $keys) { if ($palette.ContainsKey($key)) { $colors = $palette[$key]; break } }
    if (-not $colors) { $colors = $palette['default'] }
    $fg = $colors.Fg
    $bg = $colors.Bg
    if ($palette.ContainsKey('background')) { $bg = $palette['background'] }
    if ($Segment.ContainsKey('Fg')) { $fg = $Segment.Fg }
    if ($Segment.ContainsKey('Bg')) { $bg = $Segment.Bg }
    foreach ($key in $keys) {
        if ($cfg.Colors -and $cfg.Colors.ContainsKey($key)) {
            $o = $cfg.Colors[$key]
            if ($o.ContainsKey('Fg')) { $fg = $o.Fg }
            if ($o.ContainsKey('Bg')) { $bg = $o.Bg }
            break
        }
    }
    if ($cfg.Style -in 'lean', 'pure') { $bg = $null }
    @{ Fg = $fg; Bg = $bg }
}

function global:_ps10k_segment_content($Segment) {
    $icon = ''
    if ($global:P10K.Style -ne 'pure') {
        if ($Segment.IconText) { $icon = $Segment.IconText } else { $icon = _ps10k_icon $Segment.Icon }
    }
    (@($icon, $Segment.Text) | Where-Object { $_ }) -join ' '
}

# Turns raw segment results into render-ready items, dropping empty ones.
function global:_ps10k_prepare_segments($Segments) {
    $items = New-Object System.Collections.ArrayList
    foreach ($s in @($Segments)) {
        if (-not $s) { continue }
        $content = _ps10k_segment_content $s
        if (-not $content) { continue }
        $colors = _ps10k_segment_colors $s
        [void]$items.Add(@{ Content = $content; Fg = $colors.Fg; Bg = $colors.Bg })
    }
    ,$items
}

function global:_ps10k_render_powerline($Items, [switch]$Right) {
    if ($Items.Count -eq 0) { return '' }
    $sep = _ps10k_separators
    $subFg = (_ps10k_palette)['subsep'].Fg
    $reset = $global:PS10K_RESET
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        if ($Right) {
            if ($i -eq 0) { [void]$sb.Append($reset + (_ps10k_fg $item.Bg) + $sep.R) }
            else {
                $prev = $Items[$i - 1]
                if ("$($prev.Bg)" -eq "$($item.Bg)") { [void]$sb.Append((_ps10k_bg $item.Bg) + (_ps10k_fg $subFg) + $sep.SubR) }
                else { [void]$sb.Append((_ps10k_bg $prev.Bg) + (_ps10k_fg $item.Bg) + $sep.R) }
            }
        }
        elseif ($i -gt 0) {
            $prev = $Items[$i - 1]
            if ("$($prev.Bg)" -eq "$($item.Bg)") { [void]$sb.Append((_ps10k_bg $item.Bg) + (_ps10k_fg $subFg) + $sep.SubL) }
            else { [void]$sb.Append((_ps10k_bg $item.Bg) + (_ps10k_fg $prev.Bg) + $sep.L) }
        }
        [void]$sb.Append((_ps10k_bg $item.Bg) + (_ps10k_fg $item.Fg) + ' ' + $item.Content + ' ')
    }
    if (-not $Right) {
        $last = $Items[$Items.Count - 1]
        [void]$sb.Append($reset + (_ps10k_fg $last.Bg) + $sep.L)
    }
    [void]$sb.Append($reset)
    $sb.ToString()
}

function global:_ps10k_render_plain($Items) {
    if ($Items.Count -eq 0) { return '' }
    $parts = foreach ($item in $Items) { (_ps10k_fg $item.Fg) + $item.Content + $global:PS10K_RESET }
    $parts -join ' '
}

function global:_ps10k_render_side($Segments, [switch]$Right) {
    $items = _ps10k_prepare_segments $Segments
    if ($global:P10K.Style -in 'rainbow', 'classic') { return _ps10k_render_powerline $items -Right:$Right }
    _ps10k_render_plain $items
}

# The prompt char points back (vi command mode) when the vi-mode plugin says so.
function global:_ps10k_prompt_char([bool]$Success, [string]$ViMode = $global:_ps10k_state.ViMode) {
    $palette = _ps10k_palette
    $color = if ($Success) { $palette['prompt_ok'].Fg } else { $palette['prompt_error'].Fg }
    $icon = if ($ViMode -eq 'Command') { 'prompt_vicmd' } else { 'prompt' }
    (_ps10k_fg $color) + (_ps10k_icon $icon) + $global:PS10K_RESET + ' '
}

# Assembles the full prompt string from evaluated segment results.
function global:_ps10k_render_prompt {
    param($Left, $Right, [bool]$Success = $true, [int]$Width = 120)
    $cfg = $global:P10K
    $palette = _ps10k_palette
    $esc = $global:PS10K_ESC
    $reset = $global:PS10K_RESET
    $glyphs = _ps10k_glyph_class
    $leftText = _ps10k_render_side $Left
    $rightText = _ps10k_render_side $Right -Right
    $promptChar = _ps10k_prompt_char $Success

    $out = ''
    if ($cfg.EmptyLineBefore) { $out += "`n" }

    if ($cfg.MultiLine) {
        $line1 = $leftText
        $line2 = $promptChar
        if ($cfg.Frame) {
            $frame = $global:PS10K_FRAME[$glyphs]
            $frameFg = _ps10k_fg $palette['frame'].Fg
            $line1 = $frameFg + $frame.Top + $reset + $(if ($cfg.Style -in 'lean', 'pure') { ' ' } else { '' }) + $line1
            $line2 = $frameFg + $frame.Bottom + $reset + $line2
        }
        if ($rightText) {
            $gapWidth = $Width - 1 - (_ps10k_width $line1) - (_ps10k_width $rightText)
            if ($gapWidth -ge 1) {
                $gapName = if ($global:PS10K_GAPS.ContainsKey($cfg.Gap)) { $cfg.Gap } else { 'none' }
                $gapChar = $global:PS10K_GAPS[$gapName][$glyphs]
                $gap = if ($gapName -eq 'none') { ' ' * $gapWidth } else { ' ' + ($gapChar * ($gapWidth - 2)) + ' ' }
                if ($gapWidth -lt 3) { $gap = ' ' * $gapWidth }
                $line1 += (_ps10k_fg $palette['gap'].Fg) + $gap + $reset + $rightText
            }
        }
        return $out + $line1 + "`n" + $line2
    }

    $line = $leftText
    if ($cfg.Style -in 'lean', 'pure' -or -not $line) { $tail = ' ' + $promptChar } else { $tail = ' ' }
    if (-not $line) { $tail = $promptChar }
    if ($rightText) {
        $rightWidth = _ps10k_width $rightText
        $column = $Width - $rightWidth
        if ($column -gt (_ps10k_width ($line + $tail)) + 10) {
            # Save cursor, draw the right prompt, restore cursor.
            $line += "$($esc)7$($esc)[$($column)G" + $rightText + "$($esc)8"
        }
    }
    $out + $line + $tail
}
