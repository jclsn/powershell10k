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

foreach ($ps10kFile in @(Get-ChildItem -LiteralPath (Join-Path $env:PS10K_HOME 'lib') -Filter '*.ps1' | Sort-Object Name)) {
    . $ps10kFile.FullName
}
if (Test-Path -LiteralPath $global:PS10K_CUSTOM) {
    foreach ($ps10kFile in @(Get-ChildItem -LiteralPath $global:PS10K_CUSTOM -Filter '*.ps1' -File | Sort-Object Name)) {
        . $ps10kFile.FullName
    }
}

_ps10k_load_config

foreach ($ps10kPlugin in @($global:PS10K_PLUGINS)) {
    $ps10kPath = _ps10k_find_plugin $ps10kPlugin
    if ($ps10kPath) {
        try { . $ps10kPath }
        catch { Write-Warning "powershell10k: plugin '$ps10kPlugin' failed to load: $_" }
    }
    else { Write-Warning "powershell10k: plugin '$ps10kPlugin' not found" }
}

if ($global:PS10K_THEME) {
    $ps10kPath = _ps10k_find_theme $global:PS10K_THEME
    if ($ps10kPath) { . $ps10kPath }
    else { Write-Warning "powershell10k: theme '$($global:PS10K_THEME)' not found" }
}

Remove-Variable -Name ps10kFile, ps10kPlugin, ps10kPath -ErrorAction SilentlyContinue
