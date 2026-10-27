<#
.SYNOPSIS
    Removes powershell10k for the current user. No administrator rights needed.

.DESCRIPTION
    Removes the powershell10k block from your profiles. Optionally deletes the
    framework folder, ~/.p10k.ps1, the z database and the MesloLGS NF font.
    Windows Terminal settings are left alone; install.ps1 left a backup
    (settings.json.ps10k-<timestamp>.bak) next to them if you want to restore it.

.EXAMPLE
    .\uninstall.ps1
.EXAMPLE
    .\uninstall.ps1 -RemoveFiles -RemoveConfig -RemoveFonts
#>
[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:PS10K_HOME) { $env:PS10K_HOME } else { Join-Path $HOME '.powershell10k' }),
    [string[]]$ProfilePath,
    [switch]$RemoveFiles,
    [switch]$RemoveConfig,
    [switch]$RemoveFonts
)

$ErrorActionPreference = 'Stop'
$BeginMarker = '# >>> powershell10k >>>'
$EndMarker = '# <<< powershell10k <<<'

if (-not $ProfilePath) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $ProfilePath = @(
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
    )
}

foreach ($path in $ProfilePath) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $text = [IO.File]::ReadAllText($path)
    if ($text -notmatch [regex]::Escape($BeginMarker)) { continue }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($BeginMarker) + '.*?' + [regex]::Escape($EndMarker) + '\r?\n?'
    $rest = [regex]::Replace($text, $pattern, "`r`n").Trim("`r", "`n")
    if ($rest) { $rest += "`r`n" }
    [IO.File]::WriteAllText($path, $rest, (New-Object System.Text.UTF8Encoding $true))
    Write-Host "removed powershell10k from $path"
}

if ($RemoveConfig) {
    $configPath = if ($env:PS10K_CONFIG) { $env:PS10K_CONFIG } else { Join-Path $HOME '.p10k.ps1' }
    $zPath = if ($env:PS10K_Z_DATA) { $env:PS10K_Z_DATA } else { Join-Path $HOME '.ps10k_z' }
    foreach ($path in $configPath, $zPath) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force; Write-Host "removed $path" }
    }
}

if ($RemoveFonts) {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($name in 'MesloLGS NF Regular', 'MesloLGS NF Bold', 'MesloLGS NF Italic', 'MesloLGS NF Bold Italic') {
        Remove-ItemProperty -Path $regKey -Name "$name (TrueType)" -ErrorAction SilentlyContinue
        $file = Join-Path $fontDir "$name.ttf"
        # A font in use stays locked until sign-out; it is unregistered either way.
        try { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
        catch { Write-Warning "could not delete $file (in use); it is no longer registered and can be deleted after sign-out" }
    }
    Write-Host 'removed MesloLGS NF registration for the current user'
}

if ($RemoveFiles) {
    if ((Test-Path -LiteralPath $InstallDir) -and (Test-Path -LiteralPath (Join-Path $InstallDir 'powershell10k.ps1'))) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "removed $InstallDir"
    }
    else { Write-Warning "$InstallDir does not look like a powershell10k install; not deleting it" }
}

Write-Host 'powershell10k uninstalled. Open a new terminal to get your old prompt back.'
