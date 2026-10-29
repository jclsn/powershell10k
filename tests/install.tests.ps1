# install.ps1 and uninstall.ps1.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

. (Join-Path $root 'install.ps1')

Test-Case 'JSONC comments and trailing commas are handled' {
    $obj = ConvertFrom-Jsonc @'
{
    // comment
    "url": "https://example.com/a//b", /* block */
    "list": [1, 2,],
    "nested": { "quote": "say \"hi\" // not a comment", },
}
'@
    Assert-Equal 'https://example.com/a//b' $obj.url
    Assert-Equal 2 @($obj.list).Count
    Assert-Equal 'say "hi" // not a comment' $obj.nested.quote
}

Test-Case 'terminal font is set in profiles.defaults' {
    $settings = Join-Path $work 'settings.json'
    Set-Content -LiteralPath $settings -Value '{ "profiles": { "defaults": { "fontFace": "Consolas" }, "list": [ { "name": "a", "font": { "face": "Cascadia" } } ] }, }'
    Update-TerminalSettings -Path $settings -Face 'JetBrainsMono Nerd Font'
    $obj = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    Assert-Equal 'JetBrainsMono Nerd Font' $obj.profiles.defaults.font.face
    Assert-True ($null -eq $obj.profiles.defaults.fontFace)
    Assert-Equal 'JetBrainsMono Nerd Font' $obj.profiles.list[0].font.face
}

Test-Case 'PowerShell profiles in Windows Terminal get -NoLogo' {
    Assert-Equal '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo' (Add-NoLogo '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe')
    Assert-Equal '"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo' (Add-NoLogo '"C:\Program Files\PowerShell\7\pwsh.exe"')
    Assert-Equal 'pwsh.exe -nologo' (Add-NoLogo 'pwsh.exe -nologo')
    Assert-Equal 'powershell.exe -File x.ps1' (Add-NoLogo 'powershell.exe -File x.ps1')
    Assert-Equal 'cmd.exe' (Add-NoLogo 'cmd.exe')
    $settings = Join-Path $work 'settings-logo.json'
    Set-Content -LiteralPath $settings -Value '{ "profiles": { "list": [ { "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell" }, { "commandline": "cmd.exe" }, { "source": "Windows.Terminal.PowershellCore" } ] } }'
    Update-TerminalSettings -Path $settings -NoLogo
    $obj = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    Assert-Equal '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo' $obj.profiles.list[0].commandline
    Assert-Equal 'cmd.exe' $obj.profiles.list[1].commandline
    Assert-True ($null -eq $obj.profiles.list[2].commandline) 'dynamic profiles are left alone'
    Assert-True ($null -eq $obj.profiles.defaults) 'no font requested, none set'
}

Test-Case 'bundled fonts match the installer list' {
    foreach ($file in $script:FontFiles.Keys) { Assert-True (Test-Path (Join-Path $root "fonts\$file")) "missing fonts\$file" }
    foreach ($file in 'OFL.txt', 'NERD-FONTS-LICENSE.md', 'NERD-FONTS-LICENSE-AUDIT.md') {
        Assert-True (Test-Path (Join-Path $root "fonts\$file")) "font license fonts\$file missing"
    }
    Assert-True ((Get-Content (Join-Path $root 'install.ps1') -Raw) -notmatch 'Invoke-WebRequest[^\r\n]*\.ttf') 'fonts must not be downloaded'
}

Test-Case 'profile block install is idempotent and removable' {
    $profileFile = Join-Path $work 'profile.ps1'
    Set-Content -LiteralPath $profileFile -Value 'Set-Alias foo bar'
    $block = Get-ProfileBlock -Home10k 'C:\x' -ThemeName 'powerlevel10k' -PluginNames @('git')
    Install-ProfileBlock -Path $profileFile -Block $block
    Install-ProfileBlock -Path $profileFile -Block $block
    $text = [IO.File]::ReadAllText($profileFile)
    Assert-Equal 1 ([regex]::Matches($text, [regex]::Escape($script:BeginMarker)).Count)
    Assert-True ($text -match 'Set-Alias foo bar')
    Assert-Equal 'Set-Alias foo bar' (Remove-ProfileBlock $text)
}

Test-Case 'installer splits a comma separated plugin list' {
    . (Join-Path $root 'install.ps1')
    Assert-Equal 'git|z|vi-mode' ((Split-PluginList @('git,z, vi-mode')) -join '|')
    Assert-Equal 'git|z' ((Split-PluginList @('git', 'z')) -join '|')
}

Test-Case 'bundled PSReadLine is complete and installs to the user module folder' {
    $bundled = Get-ChildItem -LiteralPath (Join-Path $root 'modules\PSReadLine') -Directory | Select-Object -First 1
    $info = Test-ModuleManifest -Path (Join-Path $bundled.FullName 'PSReadLine.psd1') -ErrorAction Stop
    Assert-Equal $bundled.Name $info.Version 'folder name and manifest version'
    Assert-True (Test-Path (Join-Path $bundled.FullName 'License.txt')) 'PSReadLine license missing'
    $fakeSource = Join-Path $work 'modules-src'
    New-Item -ItemType Directory -Path (Join-Path $fakeSource 'PSReadLine\99.0.0\netstd') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeSource 'PSReadLine\99.0.0\netstd\x.dll') -Value 'x'
    $fakeModules = Join-Path $work 'user-modules'
    function Get-UserModulePath { $fakeModules }
    Install-UserPSReadLine -Source $fakeSource | Out-Null
    Assert-True (Test-Path (Join-Path $fakeModules 'PSReadLine\99.0.0\netstd\x.dll')) 'newer bundled version was not copied'
    Remove-Item -LiteralPath $fakeModules -Recurse -Force
    Install-UserPSReadLine -Source (Join-Path $root 'modules') | Out-Null
    Assert-True (-not (Test-Path $fakeModules)) 'an installed version that is new enough must be kept'
}

Test-Case 'end-to-end install and uninstall into a temp folder' {
    $target = Join-Path $work 'install'
    $profileFile = Join-Path $work 'e2e-profile.ps1'
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'install.ps1') `
        -InstallDir $target -ProfilePath $profileFile -Plugins git,z,vi-mode -SkipFont -SkipTerminal -SkipExecutionPolicy -NoPSReadLineUpgrade 2>&1
    if ($LASTEXITCODE -ne 0) { throw "install failed: $out" }
    Assert-True ([IO.File]::ReadAllText($profileFile).Contains("@('git', 'z', 'vi-mode')")) 'plugin list was not split'
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'install.ps1') `
        -InstallDir $target -ProfilePath $profileFile -SkipFont -SkipTerminal -SkipExecutionPolicy -NoPSReadLineUpgrade 2>&1
    if ($LASTEXITCODE -ne 0) { throw "re-install failed: $out" }
    Assert-True ([IO.File]::ReadAllText($profileFile).Contains("@('git', 'z', 'vi-mode')")) 're-install without -Plugins dropped the plugin list'
    Assert-True (Test-Path (Join-Path $target 'powershell10k.ps1'))
    $check = & powershell -NoProfile -NonInteractive -Command ". '$profileFile'; (Get-Command prompt).Source; if (Get-Command gst -ErrorAction SilentlyContinue) { 'gst-ok' }" 2>&1
    Assert-True ("$check" -match 'gst-ok') "profile did not load: $check"
    & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'uninstall.ps1') `
        -InstallDir $target -ProfilePath $profileFile -RemoveFiles | Out-Null
    Assert-True (-not (Test-Path $target))
    Assert-True ([IO.File]::ReadAllText($profileFile) -notmatch 'powershell10k')
}

Test-Case 'profile settings are read back from the powershell10k block' {
    $first = Join-Path $work 'settings-a.ps1'; $second = Join-Path $work 'settings-b.ps1'
    Set-Content -LiteralPath $first -Value '# no block here'
    Install-ProfileBlock -Path $second -Block (Get-ProfileBlock -Home10k 'C:\ps10k' -ThemeName 'minimal' -PluginNames @('git', 'vi-mode'))
    $settings = Get-ProfileSettings @((Join-Path $work 'missing.ps1'), $first, $second)
    Assert-Equal 'minimal' $settings.Theme
    Assert-Equal 'git vi-mode' ($settings.Plugins -join ' ')
    Assert-Equal 0 (Get-ProfileSettings @($first)).Count 'no block, no settings'
    $paths = Get-DefaultProfilePaths
    Assert-Equal 2 $paths.Count
    Assert-True ($paths[0] -like '*\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    Assert-True ($paths[1] -like '*\PowerShell\Microsoft.PowerShell_profile.ps1')
}

Test-Case 'JSON helpers and the Windows Terminal settings lookup' {
    $object = [pscustomobject]@{ a = 1 }
    Set-JsonProperty $object 'a' 2
    Set-JsonProperty $object 'b' 3
    Assert-Equal '2 3' "$($object.a) $($object.b)" 'updates and adds'
    $saved = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $work 'localappdata'
        Assert-Equal 0 @(Get-TerminalSettingsPaths).Count 'no Windows Terminal'
        $stable = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
        $unpackaged = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'
        New-Item -ItemType Directory -Path $stable, $unpackaged -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stable 'settings.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $unpackaged 'settings.json') -Value '{}'
        Assert-Equal 2 @(Get-TerminalSettingsPaths).Count 'stable and unpackaged installs'
    }
    finally { $env:LOCALAPPDATA = $saved }
}

Test-Case 'the framework copy replaces bundled files and keeps custom/' {
    $target = Join-Path $work 'copy-target'
    New-Item -ItemType Directory -Path (Join-Path $target 'custom\plugins\mine'), (Join-Path $target 'lib') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'custom\plugins\mine\mine.plugin.ps1') -Value '# mine'
    Set-Content -LiteralPath (Join-Path $target 'lib\stale.ps1') -Value '# removed upstream'
    Copy-Framework -Source $root -Target $target 6>$null
    Assert-True (Test-Path (Join-Path $target 'powershell10k.ps1'))
    Assert-True (Test-Path (Join-Path $target 'plugins\git\git.plugin.ps1'))
    Assert-True (Test-Path (Join-Path $target 'custom\plugins\mine\mine.plugin.ps1')) 'custom/ is kept'
    Assert-True (-not (Test-Path (Join-Path $target 'lib\stale.ps1'))) 'files removed upstream disappear'
    Assert-True (-not (Test-Path (Join-Path $target '.git'))) 'no .git folder'
    Assert-True ("$(Copy-Framework -Source $target -Target $target 6>&1)" -match 'nothing to copy') 'running from the install folder'
}

Test-Case 'fonts install into the given folder and registry key only once' {
    $fontDir = Join-Path $work 'fonts-target'
    $key = 'HKCU:\Software\ps10k-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        Assert-True (Install-UserFonts -Source (Join-Path $root 'fonts') -FontDir $fontDir -RegistryKey $key -NoLoad 6>$null)
        foreach ($file in $script:FontFiles.Keys) {
            Assert-True (Test-Path (Join-Path $fontDir $file)) "$file copied"
            Assert-Equal (Join-Path $fontDir $file) (Get-ItemProperty -Path $key -Name $script:FontFiles[$file]).($script:FontFiles[$file]) "$file registered"
        }
        $again = "$(Install-UserFonts -Source (Join-Path $root 'fonts') -FontDir $fontDir -RegistryKey $key -NoLoad 6>&1)"
        Assert-True ($again -match 'already installed') 'a second run skips installed fonts'
        Assert-True (-not ($again -match 'installing')) 'and copies nothing'
        $threw = $false
        Remove-Item -LiteralPath (Join-Path $fontDir 'JetBrainsMonoNerdFont-Bold.ttf')
        try { Install-UserFonts -Source (Join-Path $work 'no-fonts') -FontDir $fontDir -RegistryKey $key -NoLoad 6>$null } catch { $threw = $true }
        Assert-True $threw 'a missing bundled font is an error'
    }
    finally { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Case 'execution policy is only changed when scripts are blocked' {
    $global:_test_policy = @{ Effective = 'RemoteSigned'; Group = 'Undefined'; Set = $null }
    function global:Get-ExecutionPolicy([switch]$List) {
        if ($List) { @([pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = $global:_test_policy.Group }) }
        else { $global:_test_policy.Effective }
    }
    function global:Set-ExecutionPolicy($ExecutionPolicy, $Scope, [switch]$Force) { $global:_test_policy.Set = "$ExecutionPolicy/$Scope" }
    try {
        Set-UserExecutionPolicy 6>$null
        Assert-True ($null -eq $global:_test_policy.Set) 'RemoteSigned is left alone'
        $global:_test_policy.Effective = 'Restricted'
        Set-UserExecutionPolicy 6>$null
        Assert-Equal 'RemoteSigned/CurrentUser' $global:_test_policy.Set 'blocked: RemoteSigned for the current user'
        $global:_test_policy.Set = $null; $global:_test_policy.Group = 'AllSigned'
        $out = "$(Set-UserExecutionPolicy 6>&1)"
        Assert-True ($null -eq $global:_test_policy.Set) 'Group Policy wins'
        Assert-True ($out -match 'Group Policy')
    }
    finally { Remove-Item Function:\Get-ExecutionPolicy, Function:\Set-ExecutionPolicy, Variable:\_test_policy -ErrorAction SilentlyContinue }
}

Test-Case 'installer messages and checks' {
    Assert-True ((Test-IsAdmin) -is [bool])
    Assert-True ("$(Write-Step 'step' 6>&1)" -match '==> step')
    Assert-True ("$(Write-Info 'info' 6>&1)" -match '    info')
    Assert-True ("$(Write-Warn 'warn' 6>&1)" -match '! warn')
    $help = "$(Write-PSReadLineHelp 6>&1)"
    Assert-True ($help -match 'Save-Module PSReadLine') 'manual PSReadLine instructions'
    Assert-True ($help -match 'powershellgallery')
}

Test-Case 'uninstall removes config and data, and refuses foreign folders' {
    $config = Join-Path $work 'uninstall.p10k.ps1'; $zData = Join-Path $work 'uninstall.z'
    Set-Content -LiteralPath $config, $zData -Value 'x'
    $foreign = Join-Path $work 'not-powershell10k'
    New-Item -ItemType Directory -Path $foreign -Force | Out-Null
    $profileFile = Join-Path $work 'uninstall-profile.ps1'
    Set-Content -LiteralPath $profileFile -Value '# just mine'
    $command = "`$env:PS10K_CONFIG = '$config'; `$env:PS10K_Z_DATA = '$zData'; & '$root\uninstall.ps1' -InstallDir '$foreign' -ProfilePath '$profileFile' -RemoveConfig -RemoveFiles"
    $out = "$(& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command 2>&1 3>&1)"
    Assert-True (-not (Test-Path $config)) 'config removed'
    Assert-True (-not (Test-Path $zData)) 'z data removed'
    Assert-True (Test-Path $foreign) 'a folder without powershell10k.ps1 is not deleted'
    Assert-True ($out -match 'does not look like a powershell10k\s+install') "warning shown: $out"
    Assert-Equal '# just mine' (Get-Content -LiteralPath $profileFile) 'a profile without the block is untouched'
}

Test-Case 'the diagnostic report covers the important parts' {
    $home10k = Join-Path $work 'diag-home'
    New-Item -ItemType Directory -Path $home10k -Force | Out-Null
    $command = "`$env:PS10K_HOME = '$root'; `$env:PS10K_CONFIG = '$work\none.ps1'; `$env:PS10K_DISABLE_WIZARD = '1'; " +
        "Import-Module PSReadLine; `$global:PS10K_PLUGINS = @('git'); . '$root\powershell10k.ps1' 3>`$null; . '$root\tools\diagnose.ps1' 6>`$null"
    $saved = $env:USERPROFILE
    try {
        $env:USERPROFILE = $home10k
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command 2>&1 | Out-Null
    }
    finally { $env:USERPROFILE = $saved }
    $report = Join-Path $home10k 'ps10k-diagnose.txt'
    Assert-True (Test-Path $report) 'report saved in the home folder'
    $text = Get-Content -LiteralPath $report -Raw
    foreach ($section in '== session', '== execution policy', '== profile', '== powershell10k', '== PSReadLine', '== completion here', '== appearance: prompt config', '== appearance: Windows Terminal', '== recent errors') {
        Assert-True ($text.Contains($section)) "section $section"
    }
    Assert-True ($text -match 'loaded\s+2\.\d') 'PSReadLine version'
    Assert-True ($text -match 'PS10K_PLUGINS\s+git')
}
