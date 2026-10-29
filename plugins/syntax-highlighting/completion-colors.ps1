# Completion colors, like ls colors: folders in the prompt's folder color,
# executables green, archives red. Used by the TabExpansion2 wrapper below
# (PSReadLine's menu) and by the autosuggestions completion grid. Set
# $PS10K_HL_COMPLETION = $false to turn them off.

$global:PS10K_HL.Archives = @('.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.tbz', '.tbz2', '.xz', '.txz',
    '.zst', '.tzst', '.lz', '.lzma', '.tlz', '.lz4', '.z', '.cab', '.jar', '.war', '.ear', '.deb', '.rpm', '.cpio',
    '.arj', '.lzh', '.lha', '.ace', '.wim', '.esd', '.nupkg', '.vsix', '.appx', '.msix')

# The folder segment's color: its background in rainbow style (white text on
# blue), its text color in the other styles.
function global:_ps10k_hl_folder_color {
    if (${function:_ps10k_segment_colors}) {
        $colors = _ps10k_segment_colors @{ Name = 'dir' }
        $color = if ($global:P10K.Style -eq 'rainbow' -and $null -ne $colors.Bg) { $colors.Bg } else { $colors.Fg }
        if ($null -ne $color) { return (_ps10k_fg $color) }
    }
    "$([char]27)[38;5;39m"
}

# Executable and archive extensions as sets, rebuilt only when PATHEXT changes.
function global:_ps10k_hl_extension_sets {
    $hl = $global:PS10K_HL
    if ($hl.ExtensionSets -and $hl.ExtensionSets.PathExt -eq $env:PATHEXT) { return $hl.ExtensionSets }
    $ignoreCase = [StringComparer]::OrdinalIgnoreCase
    $sets = @{
        PathExt     = $env:PATHEXT
        Executables = New-Object 'System.Collections.Generic.HashSet[string]' $ignoreCase
        Archives    = New-Object 'System.Collections.Generic.HashSet[string]' $ignoreCase
    }
    foreach ($extension in @(($env:PATHEXT -split ';') + '.ps1')) { if ($extension) { [void]$sets.Executables.Add($extension) } }
    foreach ($extension in $hl.Archives) { [void]$sets.Archives.Add($extension) }
    $hl.ExtensionSets = $sets
    $sets
}

# The color of each completion result, or $null. $Names are the displayed
# names without escape codes (ListItemText when left out).
function global:_ps10k_hl_completion_colors($Results, [string[]]$Names) {
    $colors = New-Object string[] $Results.Count
    $sets = _ps10k_hl_extension_sets
    $folderColor = _ps10k_hl_folder_color
    for ($i = 0; $i -lt $Results.Count; $i++) {
        $type = $Results[$i].ResultType
        if ($type -eq 'ProviderContainer') { $colors[$i] = $folderColor; continue }
        if ($type -ne 'ProviderItem') { continue }
        $name = if ($Names) { $Names[$i] } else { $Results[$i].ListItemText }
        $extension = try { [IO.Path]::GetExtension($name) } catch { '' }
        if (-not $extension) { continue }
        if ($sets.Executables.Contains($extension)) { $colors[$i] = $global:PS10K_HL.Valid }
        elseif ($sets.Archives.Contains($extension)) { $colors[$i] = $global:PS10K_HL.Invalid }
    }
    , $colors
}

# One result's color, with the folder color already known.
function global:_ps10k_hl_completion_color($Result, [string]$FolderColor) {
    if ($Result.ResultType -eq 'ProviderContainer') { return $FolderColor }
    (_ps10k_hl_completion_colors @($Result))[0]
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
    $colors = _ps10k_hl_completion_colors $results
    $esc = [char]27
    for ($n = 0; $n -lt $results.Count; $n++) {
        $r = $results[$n]
        if (-not $colors[$n] -or $r.ListItemText.Contains($esc)) { continue }
        $toolTip = if ($r.ToolTip) { $r.ToolTip } else { $r.ListItemText }
        $results[$n] = New-Object System.Management.Automation.CompletionResult(
            $r.CompletionText, "$($colors[$n])$($r.ListItemText)$esc[39m", $r.ResultType, $toolTip)
    }
}

# PSReadLine gets its completions from TabExpansion2, so wrapping it colors
# both the menu and in-place cycling (which only uses CompletionText). The
# original is kept for callers that color entries themselves (the grid).
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
