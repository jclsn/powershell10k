# powershell10k: an oh-my-zsh style framework with a powerlevel10k style prompt.
#
# Dot-source this file from your PowerShell profile (install.ps1 does that):
#   $global:PS10K_THEME   = 'powerlevel10k'
#   $global:PS10K_PLUGINS = @('git', 'z')
#   . "$env:PS10K_HOME\powershell10k.ps1"
#
# Everything is defined in the global scope, so plugins and themes should use
# `function global:name` and `Set-Alias -Scope Global`.

if (-not $env:PS10K_HOME) { $env:PS10K_HOME = $PSScriptRoot }
if (-not $global:PS10K_THEME) { $global:PS10K_THEME = 'powerlevel10k' }
if ($null -eq $global:PS10K_PLUGINS) { $global:PS10K_PLUGINS = @('git') }
if (-not $global:PS10K_CUSTOM) { $global:PS10K_CUSTOM = Join-Path $env:PS10K_HOME 'custom' }

# Glyphs need UTF-8 output; Windows PowerShell defaults to the OEM code page.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

# Start from a clean slate so `ps10k reload` does not register hooks twice.
$global:PS10K_HOOKS = $null
# Load problems, shown as warnings and kept for `ps10k doctor`.
$global:PS10K_LOAD_ERRORS = New-Object System.Collections.ArrayList
function global:_ps10k_load_error([string]$Message) {
    [void]$global:PS10K_LOAD_ERRORS.Add($Message)
    Write-Warning "powershell10k: $Message"
}

foreach ($ps10kFile in @(Get-ChildItem -LiteralPath (Join-Path $env:PS10K_HOME 'lib') -Filter '*.ps1' | Sort-Object Name)) {
    . $ps10kFile.FullName
}
if (Test-Path -LiteralPath $global:PS10K_CUSTOM) {
    foreach ($ps10kFile in @(Get-ChildItem -LiteralPath $global:PS10K_CUSTOM -Filter '*.ps1' -File | Sort-Object Name)) {
        . $ps10kFile.FullName
    }
}

_ps10k_load_config

# Dropping vi-mode from the list and reloading switches back to the default keys.
if ($global:PS10K_VI_MODE -and @($global:PS10K_PLUGINS) -notcontains 'vi-mode' -and (Get-Module PSReadLine)) {
    Set-PSReadLineOption -EditMode Windows
    Remove-Variable -Name PS10K_VI_MODE -Scope Global -ErrorAction SilentlyContinue
}
# vi-mode goes first: switching PSReadLine to vi mode resets every key binding.
$ps10kPlugins = @($global:PS10K_PLUGINS | Where-Object { $_ -eq 'vi-mode' }) + @($global:PS10K_PLUGINS | Where-Object { $_ -ne 'vi-mode' })
foreach ($ps10kPlugin in $ps10kPlugins) {
    $ps10kPath = _ps10k_find_plugin $ps10kPlugin
    if ($ps10kPath) {
        try { . $ps10kPath }
        catch { _ps10k_load_error "plugin '$ps10kPlugin' failed to load: $_" }
    }
    else { _ps10k_load_error "plugin '$ps10kPlugin' not found" }
}
# These plugins skip themselves without PSReadLine; say so in an interactive
# console, where PSReadLine is normally loaded before the profile runs.
$ps10kNeedPsrl = @($ps10kPlugins | Where-Object { $_ -in 'autosuggestions', 'syntax-highlighting', 'vi-mode' })
if ($ps10kNeedPsrl -and -not (Get-Module PSReadLine) -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected) {
    _ps10k_load_error "PSReadLine is not loaded, so $($ps10kNeedPsrl -join ', ') are inactive. Run ps10k doctor."
}

if ($global:PS10K_THEME) {
    $ps10kPath = _ps10k_find_theme $global:PS10K_THEME
    if ($ps10kPath) { . $ps10kPath }
    else { _ps10k_load_error "theme '$($global:PS10K_THEME)' not found" }
}

Remove-Variable -Name ps10kFile, ps10kPlugins, ps10kPlugin, ps10kPath, ps10kNeedPsrl -ErrorAction SilentlyContinue
