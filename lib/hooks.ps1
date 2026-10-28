# Hook system, modelled after zsh's precmd, preexec and chpwd hooks.
#   precmd:  runs before every prompt is drawn.
#   chpwd:   runs before the prompt when the current location changed.
#   preexec: runs when Enter accepts a complete command line, before it runs.
#            Needs Enter bound to _ps10k_accept_line (see _ps10k_bind_accept_line).
# precmd and chpwd hooks receive the prompt context (see themes/powerlevel10k/prompt.ps1).

if (-not $global:PS10K_HOOKS) {
    $global:PS10K_HOOKS = @{
        precmd  = New-Object System.Collections.ArrayList
        chpwd   = New-Object System.Collections.ArrayList
        preexec = New-Object System.Collections.ArrayList
    }
}

function global:Add-PS10kHook {
    param(
        [Parameter(Mandatory)][ValidateSet('precmd', 'chpwd', 'preexec')][string]$Type,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    [void]$global:PS10K_HOOKS[$Type].Add($Action)
}

function global:_ps10k_run_hooks {
    param([string]$Type, $Context)
    foreach ($hook in @($global:PS10K_HOOKS[$Type])) {
        try { & $hook $Context }
        catch { Write-Warning "powershell10k: $Type hook failed: $_" }
    }
}

# Runs precmd hooks and, when the location changed, chpwd hooks.
function global:_ps10k_hooks_before_prompt {
    param($Context)
    $location = $executionContext.SessionState.Path.CurrentLocation.Path
    if ($global:_ps10k_last_location -ne $location) {
        $global:_ps10k_last_location = $location
        _ps10k_run_hooks -Type chpwd -Context $Context
    }
    _ps10k_run_hooks -Type precmd -Context $Context
}

# True when the PSReadLine buffer parses; Enter on an incomplete line only
# starts a continuation line, so preexec hooks must not run then.
function global:_ps10k_line_complete {
    $ast = $null; $tokens = $null; $parseErrors = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$cursor)
    -not $parseErrors -or $parseErrors.Count -eq 0
}

function global:_ps10k_accept_line {
    if (_ps10k_line_complete) { _ps10k_run_hooks -Type preexec }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# PSReadLine runs script key handlers in the console's normal input mode, in
# which Ctrl+c is a break signal rather than a key, and mouse and resize events
# are on. Functions with their own key loop, such as the completion menu, need
# PSReadLine's own mode, which its internal CallUsingOurInputMode restores.
# Without it (older PSReadLine), at least Ctrl+c is turned into a key.
function global:_ps10k_with_ctrl_c_as_key([scriptblock]$Action) {
    $platform = [Microsoft.PowerShell.PSConsoleReadLine].Assembly.GetType('PlatformWindows')
    $method = if ($platform) { $platform.GetMethod('CallUsingOurInputMode', [Reflection.BindingFlags]'NonPublic, Static') }
    if ($method) {
        # The delegate runs synchronously on this thread, in this scope.
        $box = @{ Result = $null; Error = $null }
        [void]$method.Invoke($null, @([Action]{ try { $box.Result = & $Action } catch { $box.Error = $_ } }))
        if ($box.Error) { throw $box.Error }
        return $box.Result
    }
    $old = $true
    try { $old = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { }
    try { & $Action }
    finally { try { [Console]::TreatControlCAsInput = $old } catch { } }
}

# Binds Enter to _ps10k_accept_line, in both vi tables when vi mode is on.
function global:_ps10k_bind_accept_line {
    if (-not (Get-Module PSReadLine)) { return }
    $handler = @{
        Chord            = 'Enter'
        BriefDescription = 'PS10kAcceptLine'
        Description      = 'Run powershell10k preexec hooks, then accept the line'
        ScriptBlock      = { _ps10k_accept_line }
    }
    Set-PSReadLineKeyHandler @handler
    if ((Get-PSReadLineOption).EditMode -eq 'Vi') { Set-PSReadLineKeyHandler @handler -ViMode Command }
}
