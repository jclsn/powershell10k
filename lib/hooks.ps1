# Hook system, modelled after zsh's precmd and chpwd hooks.
#   precmd: runs before every prompt is drawn.
#   chpwd:  runs before the prompt when the current location changed.
# Hooks receive the prompt context (see themes/powerlevel10k/prompt.ps1).

if (-not $global:PS10K_HOOKS) {
    $global:PS10K_HOOKS = @{
        precmd = New-Object System.Collections.ArrayList
        chpwd  = New-Object System.Collections.ArrayList
    }
}

function global:Add-PS10kHook {
    param(
        [Parameter(Mandatory)][ValidateSet('precmd', 'chpwd')][string]$Type,
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
