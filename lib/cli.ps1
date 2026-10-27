# The `ps10k` (like `omz`) and `p10k` commands.

function global:_ps10k_version {
    $file = Join-Path $env:PS10K_HOME 'VERSION'
    if (Test-Path -LiteralPath $file) { (Get-Content -LiteralPath $file -TotalCount 1).Trim() } else { 'unknown' }
}

function global:_ps10k_font_installed([string]$Family = 'JetBrainsMono NF') {
    foreach ($key in 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts') {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($props -and @($props.PSObject.Properties.Name | Where-Object { $_ -like "$Family*" }).Count -gt 0) { return $true }
    }
    $false
}

function global:_ps10k_doctor {
    $ok = "[ ok ]"; $warn = "[warn]"
    $psrl = Get-Module PSReadLine
    Write-Host "powershell10k $(_ps10k_version) in $env:PS10K_HOME"
    Write-Host "$ok PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    if (-not $psrl) { Write-Host "$warn PSReadLine is not loaded" }
    elseif ($psrl.Version -lt [version]'2.1.0') {
        Write-Host "$warn PSReadLine $($psrl.Version): inline suggestions and the vi-mode cursor need 2.1+."
        Write-Host '       Re-run install.ps1: it installs the bundled PSReadLine for your user (no admin, no download).'
    }
    else { Write-Host "$ok PSReadLine $($psrl.Version)" }
    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) { Write-Host "$ok git found" }
    else { Write-Host "$warn git not found: the git segment and plugin need it" }
    if (_ps10k_font_installed) { Write-Host "$ok JetBrainsMono Nerd Font installed" }
    else { Write-Host "$warn JetBrainsMono Nerd Font not installed: re-run install.ps1 or pick another Nerd Font" }
    if ($env:WT_SESSION) { Write-Host "$ok running in Windows Terminal" }
    else { Write-Host "$warn not running in Windows Terminal; glyphs and colors may not render" }
    $policy = Get-ExecutionPolicy
    if ($policy -in 'Restricted', 'AllSigned') { Write-Host "$warn execution policy is $policy; run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" }
    else { Write-Host "$ok execution policy $policy" }
    $cfg = _ps10k_config_path
    if (Test-Path -LiteralPath $cfg) { Write-Host "$ok config $cfg" } else { Write-Host "$warn no config yet, run: p10k configure" }
    Write-Host "$ok theme $($global:PS10K_THEME), plugins: $(@($global:PS10K_PLUGINS) -join ', ')"
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Host "$warn language mode is $($ExecutionContext.SessionState.LanguageMode); key handlers and the prompt need FullLanguage"
    }
    foreach ($message in @($global:PS10K_LOAD_ERRORS)) { if ($message) { Write-Host "$warn $message" } }
    Write-Host "       For a full report: . `"$env:PS10K_HOME\tools\diagnose.ps1`""
    if ($global:_ps10k_state -and $global:_ps10k_state.Errors.Count -gt 0) {
        foreach ($name in $global:_ps10k_state.Errors.Keys) { Write-Host "$warn segment ${name}: $($global:_ps10k_state.Errors[$name])" }
    }
}

function global:ps10k {
    param([Parameter(Position = 0)][string]$Command = 'help', [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
    switch ($Command) {
        'reload' {
            . (Join-Path $env:PS10K_HOME 'powershell10k.ps1')
            Write-Host 'powershell10k reloaded.'
        }
        'update' {
            if (-not (Test-Path -LiteralPath (Join-Path $env:PS10K_HOME '.git'))) {
                Write-Host "powershell10k was not installed from git. Re-run install.ps1 from a newer copy to update."
                return
            }
            git -C $env:PS10K_HOME pull --ff-only
            if ($LASTEXITCODE -eq 0) { ps10k reload }
        }
        'plugins' {
            foreach ($name in _ps10k_list_dir_names 'plugins') {
                $mark = if (@($global:PS10K_PLUGINS) -contains $name) { '*' } else { ' ' }
                "$mark $name"
            }
        }
        'themes' {
            foreach ($name in _ps10k_list_dir_names 'themes') {
                $mark = if ($global:PS10K_THEME -eq $name) { '*' } else { ' ' }
                "$mark $name"
            }
        }
        'doctor' { _ps10k_doctor }
        'version' { _ps10k_version }
        'uninstall' {
            $script = Join-Path $env:PS10K_HOME 'uninstall.ps1'
            & $script @Rest
        }
        default {
            @(
                'Usage: ps10k <command>'
                ''
                '  reload     reload configuration, plugins and theme'
                '  update     update powershell10k (git installs)'
                '  plugins    list plugins (* = enabled; edit $PS10K_PLUGINS in your profile)'
                '  themes     list themes (* = active)'
                '  doctor     check fonts, PSReadLine, git and configuration'
                '  version    print the installed version'
                '  uninstall  remove powershell10k from your profile'
            ) -join [Environment]::NewLine
        }
    }
}

function global:p10k {
    param([Parameter(Position = 0)][string]$Command = 'help')
    switch ($Command) {
        'configure' {
            if (Get-Command _ps10k_configure -ErrorAction SilentlyContinue) { _ps10k_configure }
            else { Write-Error 'p10k configure needs the powerlevel10k theme' }
        }
        'reload' { ps10k reload }
        'edit' {
            $path = _ps10k_config_path
            if (-not (Test-Path -LiteralPath $path)) { Write-Host "No config yet, run: p10k configure"; return }
            $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
            & $editor $path
        }
        'segments' {
            foreach ($name in @($global:PS10K_SEGMENTS.Keys | Sort-Object)) {
                $side = if (@($global:P10K.LeftSegments) -contains $name) { 'left ' } elseif (@($global:P10K.RightSegments) -contains $name) { 'right' } else { '     ' }
                "$side $name"
            }
        }
        default {
            @(
                'Usage: p10k <command>'
                ''
                '  configure  run the interactive configuration wizard'
                '  reload     reload the prompt configuration'
                '  edit       open ~/.p10k.ps1 in $env:EDITOR (or notepad)'
                '  segments   list prompt segments and where they are shown'
            ) -join [Environment]::NewLine
        }
    }
}
