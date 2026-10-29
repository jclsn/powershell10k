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
