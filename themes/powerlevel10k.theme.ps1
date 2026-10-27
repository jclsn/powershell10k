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

if (-not (Test-Path -LiteralPath (_ps10k_config_path)) -and -not $global:_ps10k_hinted) {
    $global:_ps10k_hinted = $true
    Write-Host 'powershell10k: run ' -NoNewline
    Write-Host 'p10k configure' -ForegroundColor Cyan -NoNewline
    Write-Host ' to customize your prompt.'
}
