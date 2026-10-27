# powerlevel10k style theme: segments, four styles, two-line layout,
# right prompt, transient prompt and an interactive `p10k configure` wizard.

$ps10kThemeDir = Join-Path $PSScriptRoot 'powerlevel10k'
foreach ($ps10kThemeFile in 'segments', 'render', 'prompt', 'configure') {
    $ps10kThemePath = Join-Path $ps10kThemeDir "$ps10kThemeFile.ps1"
    if (Test-Path -LiteralPath $ps10kThemePath) { . $ps10kThemePath }
}
Remove-Variable -Name ps10kThemeDir, ps10kThemeFile, ps10kThemePath -ErrorAction SilentlyContinue

# We draw the virtualenv segment ourselves; stop Activate.ps1 from wrapping prompt.
$env:VIRTUAL_ENV_DISABLE_PROMPT = '1'

_ps10k_setup_psreadline

# Like powerlevel10k, start the wizard on the first interactive start without a
# config. Set $env:PS10K_DISABLE_WIZARD = '1' to only print a hint instead.
if (-not (Test-Path -LiteralPath (_ps10k_config_path)) -and -not $global:_ps10k_hinted) {
    $global:_ps10k_hinted = $true
    if ((_ps10k_can_prompt) -and -not $env:PS10K_DISABLE_WIZARD) { _ps10k_configure }
    else {
        Write-Host 'powershell10k: run ' -NoNewline
        Write-Host 'p10k configure' -ForegroundColor Cyan -NoNewline
        Write-Host ' to customize your prompt.'
    }
}
