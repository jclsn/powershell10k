# The prompt function, PSReadLine integration and transient prompt.

$global:_ps10k_state = @{
    LastHistoryId = $(try { (Get-History -Count 1).Id } catch { $null })
    LastSuccess   = $true
    Transient     = $false
    Errors        = @{}
}

function global:_ps10k_term_width {
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 0) { return $w }
    }
    catch { }
    120
}

# Builds the context handed to segments and hooks.
function global:_ps10k_context([bool]$Success, $ExitCode) {
    $state = $global:_ps10k_state
    $duration = $null
    $last = Get-History -Count 1 -ErrorAction SilentlyContinue
    if ($last -and $last.Id -ne $state.LastHistoryId) {
        $state.LastHistoryId = $last.Id
        $duration = $last.EndExecutionTime - $last.StartExecutionTime
    }
    @{
        Success  = $Success
        ExitCode = $ExitCode
        Duration = $duration
        Location = $executionContext.SessionState.Path.CurrentLocation
    }
}

function global:_ps10k_eval_segments($Names, $Context) {
    $results = New-Object System.Collections.ArrayList
    foreach ($name in @($Names)) {
        $segment = $global:PS10K_SEGMENTS[$name]
        if (-not $segment) { continue }
        try {
            $result = & $segment $Context
            $global:_ps10k_state.Errors.Remove($name)
        }
        catch {
            $global:_ps10k_state.Errors[$name] = "$_"
            $result = $null
        }
        if ($result -is [hashtable]) {
            $result.Name = $name
            [void]$results.Add($result)
        }
    }
    ,$results
}

function global:_ps10k_transient_prompt {
    $out = ''
    if ($global:P10K.EmptyLineBefore) { $out += "`n" }
    # Clear the old multi-line prompt below the cursor, then draw just the prompt char.
    $out + "$($global:PS10K_ESC)[J" + (_ps10k_prompt_char $global:_ps10k_state.LastSuccess)
}

function global:_ps10k_set_title($Context) {
    $location = $Context.Location
    $path = $location.Path
    if ($location.Provider.Name -eq 'FileSystem') {
        $path = $location.ProviderPath
        if ($HOME -and $path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) { $path = '~' + $path.Substring($HOME.Length) }
    }
    $prefix = if ($global:_ps10k_is_admin) { 'Admin: ' } else { '' }
    try { $Host.UI.RawUI.WindowTitle = "$prefix$path" } catch { }
}

function global:prompt {
    $ps10kSuccess = $?
    $ps10kExitCode = $global:LASTEXITCODE
    try {
        if ($global:_ps10k_state.Transient) {
            $global:_ps10k_state.Transient = $false
            return _ps10k_transient_prompt
        }
        $cfg = $global:P10K
        $ctx = _ps10k_context $ps10kSuccess $ps10kExitCode
        $global:_ps10k_state.LastSuccess = $ps10kSuccess
        _ps10k_hooks_before_prompt $ctx

        $left = _ps10k_eval_segments $cfg.LeftSegments $ctx
        $right = _ps10k_eval_segments $cfg.RightSegments $ctx
        $text = _ps10k_render_prompt -Left $left -Right $right -Success $ps10kSuccess -Width (_ps10k_term_width)

        if ($cfg.SetTitle) { _ps10k_set_title $ctx }
        if ($cfg.ReportCwd -and $ctx.Location.Provider.Name -eq 'FileSystem') {
            # OSC 9;9 lets Windows Terminal open new tabs and panes in this directory.
            $text = "$($global:PS10K_ESC)]9;9;`"$($ctx.Location.ProviderPath)`"$($global:PS10K_ESC)\" + $text
        }
        $text
    }
    catch {
        if (-not $global:_ps10k_state.PromptError) {
            $global:_ps10k_state.PromptError = "$_"
            Write-Host "powershell10k: prompt failed, falling back to a plain prompt: $_" -ForegroundColor Red
        }
        "PS $($executionContext.SessionState.Path.CurrentLocation)> "
    }
    finally {
        $global:LASTEXITCODE = $ps10kExitCode
    }
}

function global:_ps10k_setup_psreadline {
    if (-not (Get-Module PSReadLine)) { return }
    $cfg = $global:P10K
    $extraLines = 0
    if ($cfg.MultiLine) { $extraLines++ }
    if ($cfg.EmptyLineBefore) { $extraLines++ }
    try {
        # PSReadLine colors this text red while the command line has parse errors.
        Set-PSReadLineOption -PromptText ((_ps10k_icon 'prompt') + ' ') -ExtraPromptLineCount $extraLines
    }
    catch { }

    if ($cfg.TransientPrompt) {
        Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'PS10kAcceptLine' `
            -Description 'Accept the line and collapse the prompt (powershell10k transient prompt)' -ScriptBlock {
            $ast = $null; $tokens = $null; $parseErrors = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursor)
            if (-not $parseErrors -or $parseErrors.Count -eq 0) {
                $global:_ps10k_state.Transient = $true
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    elseif ((Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Enter' }).Function -eq 'PS10kAcceptLine') {
        Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine
    }
}
