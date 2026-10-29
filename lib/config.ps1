# Prompt configuration. Defaults live here; override any key in ~/.p10k.ps1,
# which `p10k configure` writes for you. Example:
#   $P10K.Style = 'lean'
#   $P10K.RightSegments = @('status', 'time')
#   $P10K.Colors['dir'] = @{ Fg = 255; Bg = 24 }

function global:_ps10k_default_config {
    [ordered]@{
        # rainbow | classic | lean | pure
        Style             = 'rainbow'
        # nerdfont | unicode | ascii
        Mode              = 'nerdfont'
        # sharp | round | slanted (rainbow and classic only)
        Heads             = 'sharp'
        LeftSegments      = @('os_icon', 'dir', 'git')
        RightSegments     = @('status', 'command_execution_time', 'background_jobs', 'virtualenv',
                              'anaconda', 'node_version', 'aws', 'context', 'time')
        MultiLine         = $true
        # Draw connectors in front of both lines of a two-line prompt.
        Frame             = $false
        # Filler between left and right prompt on line one: none | dot | line
        Gap               = 'none'
        # Print an empty line before each prompt.
        EmptyLineBefore   = $true
        # Collapse previous prompts to just the prompt character.
        TransientPrompt   = $false
        TimeFormat        = 'HH:mm:ss'
        # Show command_execution_time only when a command ran at least this many seconds.
        ExecTimeThreshold = 3
        ExecTimePrecision = 0
        # Abbreviate middle directories once the path is longer than this; 0 disables.
        DirMaxLength      = 50
        DirSeparator      = '\'
        StatusShowOk      = $false
        # context shows user@host only when elevated or remote unless this is set.
        ContextAlwaysShow = $false
        # node_version is shown only inside a directory tree with package.json.
        NodeProjectOnly   = $true
        GitMaxBranchLength = 32
        # Update the terminal tab title and report the cwd to Windows Terminal.
        SetTitle          = $true
        ReportCwd         = $true
        # Per segment color overrides, keyed by segment or segment_state.
        Colors            = @{}
        # Per glyph overrides, see lib/icons.ps1 for names.
        Icons             = @{}
    }
}

function global:_ps10k_config_path {
    if ($env:PS10K_CONFIG) { return $env:PS10K_CONFIG }
    [IO.Path]::Combine($HOME, '.p10k.ps1')
}

function global:_ps10k_load_config {
    $global:P10K = _ps10k_default_config
    $path = _ps10k_config_path
    if ([IO.File]::Exists($path)) {
        try { . $path }
        catch { Write-Warning "powershell10k: failed to load ${path}: $_" }
    }
}
