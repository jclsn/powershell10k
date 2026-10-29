<#
.SYNOPSIS
    Installs powershell10k for the current user. No administrator rights needed.

.DESCRIPTION
    Everything is written to user locations only:
      - framework files      -> ~\.powershell10k (or -InstallDir)
      - JetBrains Mono NF    -> %LOCALAPPDATA%\Microsoft\Windows\Fonts + HKCU registry
                                (bundled in fonts\, nothing is downloaded)
      - Windows Terminal     -> its settings.json under %LOCALAPPDATA% (backed up first):
                                font, and -NoLogo for PowerShell profiles
      - PowerShell profile   -> your Documents\(Windows)PowerShell profile (backed up first)
      - execution policy     -> CurrentUser scope, only when scripts are blocked
      - PSReadLine 2.4.5     -> Documents\WindowsPowerShell\Modules (bundled in
                                modules\, only when the installed one is older)

    If scripts are blocked on your machine, start it like this:
        powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Plugins git,z,aliases -SkipFont
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME '.powershell10k'),
    [string[]]$ProfilePath,
    [string]$Theme = 'powerlevel10k',
    [string[]]$Plugins = @('git', 'z', 'aliases', 'autosuggestions', 'syntax-highlighting', 'extract', 'copypath'),
    [string]$FontFace = 'JetBrainsMono Nerd Font',
    [string[]]$TerminalSettingsPath,
    [string]$RepoUrl,
    [switch]$SkipFont,
    [switch]$SkipTerminal,
    [switch]$KeepLogo,
    [switch]$SkipProfile,
    [switch]$SkipExecutionPolicy,
    [switch]$NoPSReadLineUpgrade
)

$ErrorActionPreference = 'Stop'
# Remembered so a re-install only overrides what was passed explicitly.
$script:ExplicitParameters = @($PSBoundParameters.Keys)

$script:BeginMarker = '# >>> powershell10k >>>'
$script:EndMarker = '# <<< powershell10k <<<'
# Bundled font files (fonts\) and the names Windows registers them under.
$script:FontFiles = [ordered]@{
    'JetBrainsMonoNerdFont-Regular.ttf'    = 'JetBrainsMono NF Regular (TrueType)'
    'JetBrainsMonoNerdFont-Bold.ttf'       = 'JetBrainsMono NF Bold (TrueType)'
    'JetBrainsMonoNerdFont-Italic.ttf'     = 'JetBrainsMono NF Italic (TrueType)'
    'JetBrainsMonoNerdFont-BoldItalic.ttf' = 'JetBrainsMono NF Bold Italic (TrueType)'
}
$script:Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "    $Text" }
function Write-Warn([string]$Text) { Write-Host "    ! $Text" -ForegroundColor Yellow }

function Test-IsAdmin {
    try {
        ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $false }
}

function Get-DefaultProfilePaths {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    @(
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
    )
}

function Get-ProfileBlock([string]$Home10k, [string]$ThemeName, [string[]]$PluginNames) {
    $pluginList = ($PluginNames | ForEach-Object { "'$_'" }) -join ', '
    @(
        $script:BeginMarker
        '# Managed by powershell10k install.ps1; edit the plugin list freely.'
        "`$env:PS10K_HOME = '$($Home10k -replace "'", "''")'"
        "`$global:PS10K_THEME = '$ThemeName'"
        "`$global:PS10K_PLUGINS = @($pluginList)"
        '. (Join-Path $env:PS10K_HOME ''powershell10k.ps1'')'
        $script:EndMarker
    ) -join "`r`n"
}

# Reads the theme and plugin list from an existing powershell10k block, so a
# re-install without -Theme/-Plugins keeps what the user set up.
function Get-ProfileSettings([string[]]$Paths) {
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $text = [IO.File]::ReadAllText($path)
        $pattern = '(?s)' + [regex]::Escape($script:BeginMarker) + '(.*?)' + [regex]::Escape($script:EndMarker)
        $block = [regex]::Match($text, $pattern)
        if (-not $block.Success) { continue }
        $settings = @{}
        $theme = [regex]::Match($block.Groups[1].Value, "PS10K_THEME\s*=\s*'([^']*)'")
        if ($theme.Success) { $settings.Theme = $theme.Groups[1].Value }
        $plugins = [regex]::Match($block.Groups[1].Value, 'PS10K_PLUGINS\s*=\s*@\(([^)]*)\)')
        if ($plugins.Success) {
            $settings.Plugins = @([regex]::Matches($plugins.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        }
        return $settings
    }
    @{}
}

# Removes any existing powershell10k block from profile text.
function Remove-ProfileBlock([string]$Text) {
    if (-not $Text) { return '' }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($script:BeginMarker) + '.*?' + [regex]::Escape($script:EndMarker) + '\r?\n?'
    [regex]::Replace($Text, $pattern, "`r`n").Trim("`r", "`n")
}

function Install-ProfileBlock([string]$Path, [string]$Block) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $existing = ''
    if (Test-Path -LiteralPath $Path) {
        $existing = [IO.File]::ReadAllText($Path)
        Copy-Item -LiteralPath $Path -Destination "$Path.ps10k-$($script:Timestamp).bak" -Force
    }
    $rest = Remove-ProfileBlock $existing
    $text = if ($rest) { $rest + "`r`n`r`n" + $Block + "`r`n" } else { $Block + "`r`n" }
    [IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $true))
}

# Strips // and /* */ comments and trailing commas so JSONC parses as JSON.
function ConvertFrom-Jsonc([string]$Text) {
    $sb = New-Object System.Text.StringBuilder
    $inString = $false; $escape = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($escape) { $escape = $false }
            elseif ($c -eq '\') { $escape = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++; continue
        }
        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $Text.Length) {
            $n = $Text[$i + 1]
            if ($n -eq '/') {
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($n -eq '*') {
                $end = $Text.IndexOf('*/', $i + 2)
                $i = if ($end -lt 0) { $Text.Length } else { $end + 2 }
                continue
            }
        }
        [void]$sb.Append($c); $i++
    }
    $json = [regex]::Replace($sb.ToString(), ',(\s*[}\]])', '$1')
    $json | ConvertFrom-Json
}

function Set-JsonProperty($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-TerminalSettingsPaths {
    $local = $env:LOCALAPPDATA
    @(
        (Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $local 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $local 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path -LiteralPath $_ }
}

# Adds -NoLogo to a powershell.exe / pwsh.exe command line, which hides the
# copyright banner and the "Loading personal and system profiles took" line.
function Add-NoLogo([string]$CommandLine) {
    if ($CommandLine -notmatch '(?i)(^|[\\/"\s])(powershell|pwsh)(\.exe)?"?(\s|$)') { return $CommandLine }
    if ($CommandLine -match '(?i)\s-nol(o(go?)?)?(\s|$)') { return $CommandLine }
    # Leave command lines that run a script or command alone.
    if ($CommandLine -match '(?i)\s-(c|command|f|file|e|encodedcommand)(\s|$)') { return $CommandLine }
    $CommandLine.TrimEnd() + ' -NoLogo'
}

# Windows Terminal's built-in "Windows PowerShell" profile.
$script:WindowsPowerShellProfileGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'

function Update-TerminalSettings([string]$Path, [string]$Face, [switch]$NoLogo) {
    $settings = ConvertFrom-Jsonc ([IO.File]::ReadAllText($Path))
    if (-not $settings.PSObject.Properties['profiles']) { Set-JsonProperty $settings 'profiles' ([pscustomobject]@{}) }
    $profiles = $settings.profiles
    $list = if ($profiles -is [array]) { $profiles } else { @($profiles.list) }
    if ($NoLogo) {
        foreach ($p in $list) {
            if ($null -eq $p -or $p.PSObject.Properties['source']) { continue }
            if ($p.PSObject.Properties['commandline']) { $p.commandline = Add-NoLogo $p.commandline }
            elseif ($p.guid -eq $script:WindowsPowerShellProfileGuid) {
                Set-JsonProperty $p 'commandline' '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo'
            }
        }
    }
    if ($Face -and $profiles -is [array]) {
        # Very old schema: profiles is a plain list.
        foreach ($p in $profiles) { Set-JsonProperty $p 'fontFace' $Face }
    }
    elseif ($Face) {
        if (-not $profiles.PSObject.Properties['defaults'] -or $null -eq $profiles.defaults) {
            Set-JsonProperty $profiles 'defaults' ([pscustomobject]@{})
        }
        $defaults = $profiles.defaults
        if ($defaults.PSObject.Properties['fontFace']) { $defaults.PSObject.Properties.Remove('fontFace') }
        if (-not $defaults.PSObject.Properties['font'] -or $null -eq $defaults.font) {
            Set-JsonProperty $defaults 'font' ([pscustomobject]@{})
        }
        Set-JsonProperty $defaults.font 'face' $Face
        # A profile-level font would override the default; update those as well.
        foreach ($p in $list) {
            if ($null -eq $p) { continue }
            if ($p.PSObject.Properties['fontFace']) { $p.fontFace = $Face }
            if ($p.PSObject.Properties['font'] -and $p.font -and $p.font.PSObject.Properties['face']) { $p.font.face = $Face }
        }
    }
    Copy-Item -LiteralPath $Path -Destination "$Path.ps10k-$($script:Timestamp).bak" -Force
    $json = $settings | ConvertTo-Json -Depth 64
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

# Installs the bundled fonts for the current user: a copy in the per-user
# font folder plus a registry entry (Windows 10 1809+). -FontDir, -RegistryKey
# and -NoLoad exist for the tests, which must not touch the real ones.
function Install-UserFonts {
    param(
        [string]$Source,
        [string]$FontDir = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'),
        [string]$RegistryKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        [switch]$NoLoad
    )
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 17763) {
        Write-Warn "Per-user fonts need Windows 10 1809 or newer (this is build $build)."
        Write-Warn "Install the fonts in $Source manually (right-click > Install)."
        return $false
    }
    if (-not (Test-Path -LiteralPath $FontDir)) { New-Item -ItemType Directory -Path $FontDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $RegistryKey)) { New-Item -Path $RegistryKey -Force | Out-Null }

    $installed = @()
    foreach ($file in $script:FontFiles.Keys) {
        $target = Join-Path $FontDir $file
        $valueName = $script:FontFiles[$file]
        $registered = Get-ItemProperty -Path $RegistryKey -Name $valueName -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $target) -and $registered) { Write-Info "$file already installed"; continue }
        $bundled = Join-Path $Source $file
        if (-not (Test-Path -LiteralPath $bundled)) { throw "bundled font missing: $bundled" }
        Write-Info "installing $file"
        Copy-Item -LiteralPath $bundled -Destination $target -Force
        New-ItemProperty -Path $RegistryKey -Name $valueName -Value $target -PropertyType String -Force | Out-Null
        $installed += $target
    }
    if ($installed -and -not $NoLoad) { Register-SessionFonts $installed }
    $true
}

# Makes new fonts usable without signing out and tells running apps about
# them. Compiled only when a font was actually installed: Add-Type is slow.
function Register-SessionFonts([string[]]$Paths) {
    Add-Type -Namespace PS10k -Name Gdi -ErrorAction SilentlyContinue -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResource(string lpFileName);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    foreach ($path in $Paths) { try { [void][PS10k.Gdi]::AddFontResource($path) } catch { } }
    try {
        $result = [UIntPtr]::Zero
        # HWND_BROADCAST, WM_FONTCHANGE: tell running apps that fonts changed.
        [void][PS10k.Gdi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$result)
    }
    catch { }
}

function Copy-Framework([string]$Source, [string]$Target) {
    $src = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
    if (Test-Path -LiteralPath $Target) {
        $dst = (Resolve-Path -LiteralPath $Target).ProviderPath.TrimEnd('\')
        if ($src -eq $dst) { Write-Info "running from $Target, nothing to copy"; return }
    }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    # Replace bundled files but keep the user's custom/ folder.
    foreach ($name in 'lib', 'plugins', 'themes', 'tests') {
        $dest = Join-Path $Target $name
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    }
    Get-ChildItem -LiteralPath $src -Force | Where-Object { $_.Name -notin '.git', 'custom' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Target -Recurse -Force
    }
    $custom = Join-Path $Target 'custom'
    if (-not (Test-Path -LiteralPath $custom)) {
        $bundled = Join-Path $src 'custom'
        if (Test-Path -LiteralPath $bundled) { Copy-Item -LiteralPath $bundled -Destination $Target -Recurse -Force }
        else { New-Item -ItemType Directory -Path $custom -Force | Out-Null }
    }
}

function Set-UserExecutionPolicy {
    $effective = Get-ExecutionPolicy
    if ($effective -notin 'Restricted', 'AllSigned', 'Undefined') { Write-Info "execution policy is $effective, nothing to do"; return }
    $byPolicy = Get-ExecutionPolicy -List | Where-Object { $_.Scope -in 'MachinePolicy', 'UserPolicy' -and $_.ExecutionPolicy -ne 'Undefined' }
    if ($byPolicy) {
        Write-Warn "execution policy is enforced by Group Policy ($($byPolicy[0].ExecutionPolicy)); your profile may not load."
        return
    }
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Info 'set execution policy RemoteSigned for the current user (Windows PowerShell)'
}

# Copies the bundled PSReadLine (modules\PSReadLine\<version>) to the
# current user's Windows PowerShell module folder, unless the installed
# PSReadLine is already that new. A user module folder needs no admin rights.
function Install-UserPSReadLine([string]$Source) {
    $bundled = Get-ChildItem -LiteralPath (Join-Path $Source 'PSReadLine') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -as [version] } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $bundled) { throw "no bundled PSReadLine in $Source" }
    $version = [version]$bundled.Name
    $installed = Get-Module -ListAvailable PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed -and $installed.Version -ge $version) {
        Write-Info "PSReadLine $($installed.Version) is already installed"
        return
    }
    $target = Join-Path (Get-UserModulePath) "PSReadLine\$($bundled.Name)"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $bundled.FullName '*') -Destination $target -Recurse -Force
    Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    Write-Info "installed PSReadLine $version to $target; it is used from the next session on"
}

function Get-UserModulePath {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
}

# How to get PSReadLine by hand when the bundled copy cannot be installed.
function Write-PSReadLineHelp {
    Write-Warn 'Install PSReadLine 2.1 or newer by hand (no admin needed):'
    Write-Info '  on a machine with internet:  Save-Module PSReadLine -Path C:\temp\modules'
    Write-Info "  then copy C:\temp\modules\PSReadLine to $(Get-UserModulePath)\"
    Write-Info '  or download the .nupkg from https://www.powershellgallery.com/packages/PSReadLine,'
    Write-Info '  rename it to .zip and extract it to that folder as PSReadLine\<version>'
}

# `powershell -File install.ps1 -Plugins a,b` passes the list as one string.
function Split-PluginList([string[]]$Names) {
    @($Names | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
}

function Invoke-Install {
    $script:Plugins = Split-PluginList $Plugins
    Write-Host ''
    Write-Host 'powershell10k installer (no administrator rights required)' -ForegroundColor Green
    Write-Host ''
    if (Test-IsAdmin) { Write-Warn 'You are running elevated. That is not needed; everything installs for the current user.' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw "powershell10k needs PowerShell 5.1 or newer (found $($PSVersionTable.PSVersion))." }

    Write-Step "Installing framework to $InstallDir"
    if ($RepoUrl) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw '-RepoUrl needs git on PATH.' }
        if (Test-Path -LiteralPath (Join-Path $InstallDir '.git')) { git -C $InstallDir pull --ff-only }
        else { git clone --depth 1 $RepoUrl $InstallDir }
        if ($LASTEXITCODE -ne 0) { throw 'git failed' }
    }
    else {
        if (-not $PSScriptRoot) { throw 'Run install.ps1 from a downloaded copy, or pass -RepoUrl to clone.' }
        Copy-Framework -Source $PSScriptRoot -Target $InstallDir
    }
    # Downloaded zips mark files as coming from the internet; RemoteSigned would block them.
    Get-ChildItem -LiteralPath $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    $InstallDir = (Resolve-Path -LiteralPath $InstallDir).ProviderPath

    if (-not $SkipFont) {
        Write-Step "Installing $FontFace font for the current user"
        try { [void](Install-UserFonts -Source (Join-Path $InstallDir 'fonts')) }
        catch { Write-Warn "font installation failed: $_" }
    }

    if (-not $SkipTerminal) {
        Write-Step 'Configuring Windows Terminal'
        $paths = if ($TerminalSettingsPath) { $TerminalSettingsPath } else { @(Get-TerminalSettingsPaths) }
        if (-not $paths) { Write-Info "Windows Terminal settings not found; set the font to $FontFace yourself." }
        foreach ($path in $paths) {
            try {
                Update-TerminalSettings -Path $path -Face $FontFace -NoLogo:(-not $KeepLogo)
                Write-Info "font$(if (-not $KeepLogo) { ' and -NoLogo' }) set in $path (backup next to it)"
            }
            catch { Write-Warn "could not update ${path}: $_" }
        }
    }

    if (-not $SkipProfile) {
        Write-Step 'Updating PowerShell profiles'
        $paths = if ($ProfilePath) { $ProfilePath } else { Get-DefaultProfilePaths }
        $previous = Get-ProfileSettings $paths
        if ($previous.Plugins -and $script:ExplicitParameters -notcontains 'Plugins') {
            $Plugins = $previous.Plugins
            Write-Info "keeping your plugins: $($Plugins -join ', ') (pass -Plugins to change them)"
        }
        if ($previous.Theme -and $script:ExplicitParameters -notcontains 'Theme') { $Theme = $previous.Theme }
        $block = Get-ProfileBlock -Home10k $InstallDir -ThemeName $Theme -PluginNames $Plugins
        foreach ($path in $paths) { Install-ProfileBlock -Path $path -Block $block; Write-Info $path }
    }

    if (-not $SkipExecutionPolicy) {
        Write-Step 'Checking execution policy'
        try { Set-UserExecutionPolicy } catch { Write-Warn "could not set execution policy: $_" }
    }

    if (-not $NoPSReadLineUpgrade) {
        Write-Step 'Checking PSReadLine'
        try { Install-UserPSReadLine -Source (Join-Path $InstallDir 'modules') }
        catch {
            Write-Warn "could not install the bundled PSReadLine: $_"
            Write-PSReadLineHelp
        }
    }

    Write-Host ''
    Write-Host 'Done!' -ForegroundColor Green
    Write-Host '  1. Restart Windows Terminal so it picks up the new font.'
    Write-Host '  2. Open a new PowerShell tab: the configuration wizard starts automatically.'
    Write-Host '     Run it again any time with: p10k configure'
    Write-Host '  Uninstall with: ps10k uninstall'
    Write-Host ''
}

# Dot-sourcing (". .\install.ps1") only loads the functions, for tests.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Install }
