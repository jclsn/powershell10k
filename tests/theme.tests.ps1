# The powerlevel10k theme: segments, rendering, prompt, wizard.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'duration formatting' {
    Assert-Equal '4s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 0)
    Assert-Equal '4.70s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 2)
    Assert-Equal '1m 5s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(65)) 0)
    Assert-Equal '1h 0m 1s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(3601)) 0)
}

Test-Case 'long paths are shortened in the middle' {
    $long = 'C:\Users\someone\projects\.config\very-long-directory-name\leaf'
    Assert-Equal 'C:\U\s\p\.config\very-long-directory-name\leaf' ((_ps10k_shorten_path $long 46 '\') -join '\')
    Assert-Equal 'C:\U\s\p\.c\v\leaf' ((_ps10k_shorten_path $long 10 '\') -join '\')
    $parts = _ps10k_shorten_path 'C:\short' 30 '\'
    Assert-Equal 'C:\short' ($parts -join '\')
}

Test-Case 'prompt renders in every style and layout' {
    foreach ($style in 'rainbow', 'classic', 'lean', 'pure') {
        foreach ($multi in $true, $false) {
            $P10K.Style = $style; $P10K.MultiLine = $multi
            $text = prompt
            Assert-True ($text -match 'tests|powershell10k') "style $style missing directory"
            Assert-True ($text -notmatch '^PS ') "style $style fell back to the plain prompt: $($global:_ps10k_state.PromptError)"
        }
    }
    _ps10k_load_config
}

Test-Case 'two-line prompt fills the first line to the terminal width' {
    $left = @(@{ Name = 'dir'; Icon = 'folder'; Text = 'C:\x' })
    $right = @(@{ Name = 'time'; Icon = 'time'; Text = '12:00:00' })
    foreach ($gap in 'none', 'dot', 'line') {
        $P10K.Gap = $gap
        $text = _ps10k_render_prompt -Left $left -Right $right -Width 80
        $line1 = ($text -split "`n")[1]
        Assert-Equal 79 (_ps10k_width $line1) "gap $gap"
    }
    _ps10k_load_config
}

Test-Case 'status segment shows the exit code' {
    $seg = & $global:PS10K_SEGMENTS['status'] @{ Success = $false; ExitCode = 2 }
    Assert-Equal '2' $seg.Text
    Assert-Equal 'error' $seg.State
    Assert-True ($null -eq (& $global:PS10K_SEGMENTS['status'] @{ Success = $true; ExitCode = 0 }))
}

Test-Case 'prompt preserves LASTEXITCODE' {
    $global:LASTEXITCODE = 7
    $null = prompt
    Assert-Equal 7 $global:LASTEXITCODE
}

Test-Case 'configure writes a config that loads back' {
    $answers = [ordered]@{ Mode = 'unicode'; Style = 'lean'; MultiLine = $false; RightSegments = @('status', 'time'); TransientPrompt = $true }
    Set-Content -LiteralPath $env:PS10K_CONFIG -Value (_ps10k_wizard_config_text $answers) -Encoding UTF8
    _ps10k_load_config
    Assert-Equal 'lean' $P10K.Style
    Assert-Equal 'unicode' $P10K.Mode
    Assert-Equal $false $P10K.MultiLine
    Assert-Equal 'status time' "$($P10K.RightSegments)"
    Remove-Item -LiteralPath $env:PS10K_CONFIG
    _ps10k_load_config
}

# Runs a segment like the prompt does, in $Path (a folder or a provider path).
function Invoke-TestSegment([string]$Name, [string]$Path = $root, [hashtable]$Context = @{}) {
    Push-Location -LiteralPath $Path
    try {
        $ctx = @{ Success = $true; ExitCode = 0; Duration = $null; Location = $executionContext.SessionState.Path.CurrentLocation }
        foreach ($key in $Context.Keys) { $ctx[$key] = $Context[$key] }
        & $global:PS10K_SEGMENTS[$Name] $ctx
    }
    finally { Pop-Location }
}

# Runs $Body with a fresh default configuration and restores the old one.
function Use-TestConfig([scriptblock]$Body) {
    $saved = $global:P10K
    try { $global:P10K = _ps10k_default_config; & $Body }
    finally { $global:P10K = $saved }
}

Test-Case 'dir segment shortens home, bolds the last folder and handles other drives' {
    Use-TestConfig {
        $homeDir = Invoke-TestSegment 'dir' $HOME
        Assert-Equal '~' $homeDir.Text
        Assert-Equal 'home' $homeDir.Icon
        $repo = Invoke-TestSegment 'dir' $root
        Assert-True ($repo.Text.EndsWith("$($global:PS10K_BOLD)powershell10k$($global:PS10K_NOBOLD)")) 'last folder in bold'
        Assert-Equal "$env:SystemDrive\" (Invoke-TestSegment 'dir' "$env:SystemDrive\").Text 'drive root keeps its separator'
        $registry = Invoke-TestSegment 'dir' 'HKCU:\Software'
        Assert-Equal 'folder' $registry.Icon
        Assert-True ($registry.Text -match 'HKCU:') 'other providers show their path'
        $global:P10K.Style = 'pure'
        Assert-True (-not (Invoke-TestSegment 'dir' $root).Text.Contains($global:PS10K_BOLD)) 'pure style is not bold'
    }
}

Test-Case 'status, execution time, jobs and time segments' {
    Use-TestConfig {
        Assert-True ($null -eq (Invoke-TestSegment 'status'))
        $global:P10K.StatusShowOk = $true
        Assert-Equal 'ok' (Invoke-TestSegment 'status').State
        $global:P10K.Mode = 'ascii'
        $failed = Invoke-TestSegment 'status' -Context @{ Success = $false; ExitCode = 3 }
        Assert-True ($null -eq $failed.Icon) 'ascii mode shows just the code'
        Assert-Equal '' (Invoke-TestSegment 'status' -Context @{ Success = $false; ExitCode = 0 }).Text 'a failed cmdlet has no exit code'
        Assert-True ($null -eq (Invoke-TestSegment 'command_execution_time' -Context @{ Duration = [TimeSpan]::FromSeconds(1) })) 'below the threshold'
        Assert-Equal '5s' (Invoke-TestSegment 'command_execution_time' -Context @{ Duration = [TimeSpan]::FromSeconds(5) }).Text
        Assert-True ($null -eq (Invoke-TestSegment 'command_execution_time')) 'no command ran'
        $global:P10K.TimeFormat = 'yyyy'
        Assert-Equal (Get-Date -Format 'yyyy') (Invoke-TestSegment 'time').Text
        Assert-True ($null -eq (Invoke-TestSegment 'background_jobs'))
        $job = Start-Job { Start-Sleep -Seconds 30 }
        try {
            while ($job.State -ne 'Running') { Start-Sleep -Milliseconds 50 }
            Assert-Equal 'jobs' (Invoke-TestSegment 'background_jobs').Icon
            Assert-Equal '' (Invoke-TestSegment 'background_jobs').Text 'one job shows just the icon'
        }
        finally { $job | Remove-Job -Force }
    }
}

Test-Case 'environment segments: virtualenv, anaconda, aws and context' {
    $names = 'VIRTUAL_ENV', 'CONDA_DEFAULT_ENV', 'AWS_VAULT', 'AWS_PROFILE', 'AWS_DEFAULT_PROFILE', 'SSH_CONNECTION', 'SSH_CLIENT'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        Use-TestConfig {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $null) }
            foreach ($segment in 'virtualenv', 'anaconda', 'aws') { Assert-True ($null -eq (Invoke-TestSegment $segment)) "$segment hidden" }
            $env:VIRTUAL_ENV = 'C:\envs\project-venv'
            Assert-Equal 'project-venv' (Invoke-TestSegment 'virtualenv').Text
            $env:CONDA_DEFAULT_ENV = 'base'
            Assert-Equal 'base' (Invoke-TestSegment 'anaconda').Text
            $env:AWS_DEFAULT_PROFILE = 'default'; $env:AWS_PROFILE = 'dev'
            Assert-Equal 'dev' (Invoke-TestSegment 'aws').Text 'AWS_PROFILE wins over the default'
            $env:AWS_VAULT = 'vault'
            Assert-Equal 'vault' (Invoke-TestSegment 'aws').Text 'aws-vault wins'
            if (-not $global:_ps10k_is_admin) {
                Assert-True ($null -eq (Invoke-TestSegment 'context')) 'hidden locally'
                $env:SSH_CONNECTION = '1.2.3.4 22 5.6.7.8 22'
                Assert-Equal 'remote' (Invoke-TestSegment 'context').State
                Assert-Equal "$env:USERNAME@$env:COMPUTERNAME" (Invoke-TestSegment 'context').Text
            }
            $env:SSH_CONNECTION = $null
            $global:P10K.ContextAlwaysShow = $true
            Assert-True ($null -ne (Invoke-TestSegment 'context')) 'shown when always on'
        }
    }
    finally { foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) } }
}

Test-Case 'project segments: node, dotnet and find-up' {
    $project = Join-Path $work 'project\src'
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    Assert-True ($null -eq (_ps10k_find_up $project @('package.json')))
    Set-Content -LiteralPath (Join-Path $work 'project\package.json') -Value '{}'
    Assert-Equal (Join-Path $work 'project\package.json') (_ps10k_find_up $project @('nope.txt', 'package.json')) 'found in a parent'
    Use-TestConfig {
        Assert-True ($null -eq (Invoke-TestSegment 'node_version' $env:SystemRoot)) 'node only inside a project'
        if (Get-Command node -CommandType Application -ErrorAction Ignore) {
            Assert-True ((Invoke-TestSegment 'node_version' $project).Text -match '^\d+\.') 'node version'
        }
        Assert-True ($null -eq (Invoke-TestSegment 'dotnet_version' $project)) 'dotnet only next to a project file'
        Assert-True ($null -eq (Invoke-TestSegment 'node_version' 'HKCU:\Software')) 'not on other providers'
    }
}

Test-Case 'segment colors: palette, states and user overrides' {
    Use-TestConfig {
        Assert-Equal 4 (_ps10k_segment_colors @{ Name = 'dir' }).Bg 'rainbow folder background'
        $modified = _ps10k_segment_colors @{ Name = 'git'; State = 'modified' }
        $clean = _ps10k_segment_colors @{ Name = 'git'; State = 'clean' }
        Assert-True ("$($modified.Bg)" -ne "$($clean.Bg)") 'states have their own colors'
        $global:P10K.Colors['dir'] = @{ Fg = 1; Bg = 2 }
        $dir = _ps10k_segment_colors @{ Name = 'dir' }
        Assert-Equal '1 2' "$($dir.Fg) $($dir.Bg)" 'user override'
        Assert-Equal 9 (_ps10k_segment_colors @{ Name = 'custom'; Fg = 9 }).Fg 'segments can bring their own colors'
        $global:P10K.Style = 'lean'
        Assert-True ($null -eq (_ps10k_segment_colors @{ Name = 'git' }).Bg) 'lean has no backgrounds'
        $global:P10K.Style = 'nonsense'
        Assert-True ($null -ne (_ps10k_palette)) 'unknown styles fall back to rainbow'
    }
}

Test-Case 'segments render as powerline or plain text' {
    Use-TestConfig {
        $segments = @(
            @{ Name = 'dir'; Icon = 'folder'; Text = 'a' },
            @{ Name = 'dir'; Icon = 'folder'; Text = 'b' },
            @{ Name = 'git'; IconText = '*'; Text = 'main' },
            @{ Name = 'empty'; Text = '' },
            $null
        )
        $items = _ps10k_prepare_segments $segments
        Assert-Equal 3 $items.Count 'empty segments are dropped'
        Assert-Equal '* main' $items[2].Content 'IconText is used as is'
        $left = _ps10k_strip_ansi (_ps10k_render_powerline $items)
        Assert-True ($left.Contains([string][char]0xE0B1)) 'same background: thin separator'
        Assert-True ($left.EndsWith([string][char]0xE0B0)) 'ends with a head'
        $right = _ps10k_strip_ansi (_ps10k_render_powerline $items -Right)
        Assert-True ($right.StartsWith([string][char]0xE0B2)) 'right side starts with a head'
        Assert-Equal '' (_ps10k_render_powerline @())
        $global:P10K.Style = 'pure'
        Assert-Equal 'main' (_ps10k_segment_content @{ Name = 'git'; Icon = 'branch'; Text = 'main' }) 'pure has no icons'
        Assert-Equal 'a b main' (_ps10k_strip_ansi (_ps10k_render_side $segments[0..2])) 'plain styles join with spaces'
    }
}

Test-Case 'prompt char, transient prompt and the full prompt' {
    Use-TestConfig {
        Assert-True ((_ps10k_prompt_char $true 'Insert') -ne (_ps10k_prompt_char $false 'Insert')) 'success and failure differ in color'
        Assert-Equal "$([char]0x276E) " (_ps10k_strip_ansi (_ps10k_prompt_char $true 'Command')) 'vi command mode'
        $global:_ps10k_state.LastSuccess = $true
        Assert-True ((_ps10k_strip_ansi (_ps10k_transient_prompt)).EndsWith("$([char]0x276F) ")) 'transient prompt is only the prompt char'
        $text = prompt
        Assert-True ($text.Contains("$([char]27)]9;9;")) 'reports the folder to Windows Terminal'
        Assert-True ((_ps10k_strip_ansi $text).StartsWith("`n")) 'empty line before'
        $global:P10K.ReportCwd = $false
        Assert-True (-not (prompt).Contains(']9;9;'))
        Assert-True ((_ps10k_term_width) -gt 0)
    }
}

Test-Case 'segment errors are recorded and the prompt falls back when it breaks' {
    Use-TestConfig {
        $global:PS10K_SEGMENTS['broken'] = { throw 'segment broke' }
        try {
            $results = _ps10k_eval_segments @('broken', 'no-such-segment', 'time') @{}
            Assert-Equal 1 $results.Count 'broken and unknown segments are skipped'
            Assert-True ($global:_ps10k_state.Errors['broken'] -match 'segment broke')
            $global:PS10K_SEGMENTS['broken'] = { @{ Text = 'fixed' } }
            [void](_ps10k_eval_segments @('broken') @{})
            Assert-True (-not $global:_ps10k_state.Errors.ContainsKey('broken')) 'error cleared once it works'
        }
        finally { $global:PS10K_SEGMENTS.Remove('broken') }
        $savedRender = ${function:_ps10k_render_prompt}
        try {
            Set-Item Function:\global:_ps10k_render_prompt -Value { throw 'render broke' }
            $global:_ps10k_state.PromptError = $null
            $text = prompt 6>$null
            Assert-True ($text -match '^PS .*> $') 'plain fallback prompt'
            Assert-True ($global:_ps10k_state.PromptError -match 'render broke')
        }
        finally { Set-Item Function:\global:_ps10k_render_prompt -Value $savedRender; $global:_ps10k_state.PromptError = $null }
    }
}

Test-Case 'wizard builds and previews configurations' {
    $cfg = _ps10k_wizard_config @{ Style = 'classic'; Heads = 'round' }
    Assert-Equal 'classic' $cfg.Style
    Assert-Equal 'round' $cfg.Heads
    Assert-Equal 'nerdfont' $cfg.Mode 'other keys keep their defaults'
    $text = _ps10k_wizard_config_text ([ordered]@{ Style = 'lean'; MultiLine = $true; RightSegments = @('time') })
    Assert-True ($text.Contains("`$P10K.Style = 'lean'"))
    Assert-True ($text.Contains('$P10K.MultiLine = $true'))
    Assert-True ($text.Contains("`$P10K.RightSegments = @('time')"))
    $preview = @(_ps10k_wizard_preview @{ Style = 'rainbow' } 'Label' 6>&1) -join "`n"
    Assert-True ($preview -match 'Label')
    Assert-True ($preview -match 'powershell10k') 'sample folder in the preview'
    # Only decidable here when input is redirected; in a terminal there is a console.
    if ([Console]::IsInputRedirected) { Assert-True (-not (_ps10k_can_prompt)) 'no wizard without an interactive console' }
    else { Assert-True ((_ps10k_can_prompt) -is [bool]) }
}

Test-Case 'minimal theme renders a one-line prompt' {
    $script = "`$env:PS10K_HOME = '$root'; `$env:PS10K_CONFIG = '$work\none.ps1'; `$global:PS10K_THEME = 'minimal'; `$global:PS10K_PLUGINS = @(); " +
        ". '$root\powershell10k.ps1'; Set-Location '$root'; prompt"
    $out = "$(& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $script 2>&1)"
    Assert-True ($out -match 'powershell10k') "folder in the prompt: $out"
    Assert-True ((_ps10k_strip_ansi $out) -match '> $') 'ends with the prompt char'
}

# Runs the wizard with $Keys as the answers, without a console.
function Invoke-TestWizard([string[]]$Keys) {
    $global:_test_keys = [System.Collections.Queue]::new([object[]]$Keys)
    $saved = @{}
    foreach ($name in '_ps10k_can_prompt', '_ps10k_wizard_key', '_ps10k_wizard_header', 'Clear-Host') {
        $saved[$name] = Get-Item -LiteralPath "Function:\$name" -ErrorAction Ignore
    }
    Set-Item Function:\global:_ps10k_can_prompt -Value { $true }
    Set-Item Function:\global:_ps10k_wizard_header -Value { }
    Set-Item Function:\global:Clear-Host -Value { }
    Set-Item Function:\global:_ps10k_wizard_key -Value {
        $key = $global:_test_keys.Dequeue()
        if ($key -eq 'r') { throw 'PS10K_WIZARD_RESTART' }
        $key
    }
    try { _ps10k_configure 6>&1 | Out-String }
    finally {
        foreach ($name in $saved.Keys) {
            if ($saved[$name]) { Set-Item -LiteralPath "Function:\global:$name" -Value $saved[$name].ScriptBlock }
            else { Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue }
        }
        Remove-Variable -Name _test_keys -Scope Global -ErrorAction SilentlyContinue
    }
}

Test-Case 'the wizard writes the chosen configuration' {
    $savedPath = $env:PS10K_CONFIG; $savedConfig = $global:P10K
    try {
        $env:PS10K_CONFIG = Join-Path $work 'wizard.p10k.ps1'
        # diamond yes, rainbow, round heads, 24h time, two lines, dotted, frame, sparse, transient, save
        $out = Invoke-TestWizard @('y', '3', '2', '1', '2', '2', 'y', '2', 'y', 'y')
        Assert-True ($out -match 'configuration saved') 'saved'
        $text = Get-Content -LiteralPath $env:PS10K_CONFIG -Raw
        foreach ($expected in "Style = 'rainbow'", "Heads = 'round'", "Gap = 'dot'", 'Frame = $true', 'EmptyLineBefore = $true', 'TransientPrompt = $true', "TimeFormat = 'HH:mm:ss'") {
            Assert-True ($text.Contains($expected)) "config has $expected"
        }
        Assert-Equal 'rainbow' $global:P10K.Style 'and it is loaded right away'
        # no diamond, no check mark: ascii; lean (no heads question), no time, one line, compact, no transient, restart
        $out = Invoke-TestWizard @('n', 'n', '1', 'n', '1', '1', 'n', 'r', 'n', 'y', '4', 'n', '1', '1', 'n', 'n')
        Assert-True ($out -match 'cancelled') 'restart, then quit without saving'
        Assert-True ((Get-Content -LiteralPath $env:PS10K_CONFIG -Raw).Contains("Style = 'rainbow'")) 'nothing was changed'
        Assert-True (-not (Test-Path "$env:PS10K_CONFIG.bak")) 'no backup without saving'
        $out = Invoke-TestWizard @('n', 'y', '4', 'n', '1', '1', 'n', 'y')
        $text = Get-Content -LiteralPath $env:PS10K_CONFIG -Raw
        Assert-True ($text.Contains("Mode = 'unicode'") -and $text.Contains("Style = 'pure'")) 'unicode pure'
        Assert-True (-not $text.Contains("'time'")) 'time removed from the right side'
        Assert-True (Test-Path "$env:PS10K_CONFIG.bak") 'the old config is backed up'
    }
    finally { $env:PS10K_CONFIG = $savedPath; $global:P10K = $savedConfig; _ps10k_setup_psreadline }
}

Test-Case 'PSReadLine setup and the window title follow the configuration' {
    Use-TestConfig {
        $global:P10K.MultiLine = $true; $global:P10K.EmptyLineBefore = $true
        _ps10k_setup_psreadline
        Assert-Equal 2 (Get-PSReadLineOption).ExtraPromptLineCount 'two-line prompt with an empty line'
        Assert-Equal "$(_ps10k_icon 'prompt') " ((Get-PSReadLineOption).PromptText -join '') 'prompt text for error coloring'
        $global:P10K.MultiLine = $false; $global:P10K.EmptyLineBefore = $false
        _ps10k_setup_psreadline
        Assert-Equal 0 (Get-PSReadLineOption).ExtraPromptLineCount
        $savedTitle = try { $Host.UI.RawUI.WindowTitle } catch { $null }
        Push-Location -LiteralPath $root
        try {
            _ps10k_set_title @{ Location = $executionContext.SessionState.Path.CurrentLocation }
            $title = try { $Host.UI.RawUI.WindowTitle } catch { $null }
            if ($null -ne $title) { Assert-True ($title -like '*powershell10k') "title is the folder: $title" }
        }
        finally { Pop-Location; if ($null -ne $savedTitle) { try { $Host.UI.RawUI.WindowTitle = $savedTitle } catch { } } }
    }
    _ps10k_setup_psreadline
}

Test-Case 'the prompt context measures the last command' {
    $state = $global:_ps10k_state
    $state.LastHistoryId = -1
    Get-Date | Out-Null
    $ctx = _ps10k_context $false 5
    Assert-Equal $false $ctx.Success
    Assert-Equal 5 $ctx.ExitCode
    Assert-Equal (Get-Location).Path $ctx.Location.Path
    $again = _ps10k_context $true 0
    Assert-True ($null -eq $again.Duration) 'no new command, no duration'
}
