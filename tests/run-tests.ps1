<#
.SYNOPSIS
    Dependency-free test runner for powershell10k.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Area git, plugins
#>
param(
    # Only these test files; core always runs because it loads the framework.
    [string[]]$Area
)
$ErrorActionPreference = 'Stop'
# powershell -File gets "-Area a, b" as separate words, not as a list: the
# first lands in $Area, the rest in $args, possibly with trailing commas.
$Area = @(@($Area) + @($args) | ForEach-Object { "$_" -split '[,\s]+' } | Where-Object { $_ })
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ("ps10k-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null

$script:Passed = 0
$script:Failed = 0

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:Passed++
        Write-Host "  [pass] $Name" -ForegroundColor Green
    }
    catch {
        $script:Failed++
        Write-Host "  [FAIL] $Name`n         $_" -ForegroundColor Red
    }
}

function Assert-Equal($Expected, $Actual, [string]$Message = '') {
    if ("$Expected" -ne "$Actual") { throw "expected '$Expected' but got '$Actual' $Message" }
}

function Assert-True($Value, [string]$Message = 'expected true') {
    if (-not $Value) { throw $Message }
}

# Framework setup shared by all test files.

$env:PS10K_HOME = $root
$env:PS10K_CONFIG = Join-Path $work 'p10k.ps1'
$env:PS10K_Z_DATA = Join-Path $work 'z'
$env:PS10K_DISABLE_WIZARD = '1'
# The bundled PSReadLine when the installed one is older (CI runners, fresh
# machines): several features and their tests need 2.1+.
$bundledPsrl = Get-ChildItem -LiteralPath (Join-Path $root 'modules\PSReadLine') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
$installedPsrl = Get-Module -ListAvailable PSReadLine | Sort-Object Version | Select-Object -Last 1
if ($bundledPsrl -and (-not $installedPsrl -or $installedPsrl.Version -lt [version]$bundledPsrl.Name)) {
    Import-Module (Join-Path $bundledPsrl.FullName 'PSReadLine.psd1') -ErrorAction SilentlyContinue
}
else { Import-Module PSReadLine -ErrorAction SilentlyContinue }
Write-Host "PowerShell $($PSVersionTable.PSVersion), PSReadLine $((Get-Module PSReadLine).Version)"
$global:PS10K_PLUGINS = @('git', 'z', 'aliases', 'autosuggestions', 'syntax-highlighting', 'extract', 'web-search', 'copypath')
$global:PS10K_THEME = 'powerlevel10k'

# One file per area, in this order: later files rely on the framework the
# core tests load.
foreach ($name in 'static', 'core', 'git', 'theme', 'highlighting', 'completion', 'plugins', 'install') {
    if ($Area -and $name -ne 'core' -and $Area -notcontains $name) { continue }
    Write-Host $name
    . (Join-Path $PSScriptRoot "$name.tests.ps1")
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
$color = if ($script:Failed -eq 0) { 'Green' } else { 'Red' }
Write-Host "$($script:Passed) passed, $($script:Failed) failed" -ForegroundColor $color
exit ([int]($script:Failed -gt 0))
