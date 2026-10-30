# Loader and lib/: width, colors, cd.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'loader loads every plugin without warnings' {
    $warnings = . (Join-Path $root 'powershell10k.ps1') 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
    if ($warnings) { throw "warnings: $($warnings -join '; ')" }
    Assert-True (Get-Command prompt -CommandType Function)
    Assert-True (Get-Command gst -CommandType Function)
    Assert-True (Get-Command z -CommandType Function)
}

Test-Case 'display width ignores escape sequences' {
    Assert-Equal 3 (_ps10k_width "$([char]27)[38;5;1mabc$([char]27)[0m")
    Assert-Equal 2 (_ps10k_width ([string][char]0x4E2D))
    Assert-Equal 9 (_ps10k_width ("$([char]0xDC)bersicht")) 'umlauts are one column'
    Assert-Equal 3 (_ps10k_width ("a" + [char]::ConvertFromUtf32(0x1F600) + "$([char]1)")) 'emoji two columns, control characters none'
    Assert-Equal 5 (_ps10k_width 'plain') 'ASCII fast path'
    Assert-Equal 1 (_ps10k_width "$([char]27)]9;9;`"C:\`"$([char]27)\x")
}

Test-Case 'colors accept indexes, names and hex' {
    Assert-Equal "$([char]27)[38;5;4m" (_ps10k_fg 4)
    Assert-Equal "$([char]27)[48;5;1m" (_ps10k_bg 'red')
    Assert-Equal "$([char]27)[38;2;255;0;16m" (_ps10k_fg '#ff0010')
    Assert-Equal '' (_ps10k_fg $null)
}

Test-Case 'cd without arguments goes home' {
    Push-Location
    try {
        Set-Location -LiteralPath $env:SystemRoot
        cd
        Assert-Equal $HOME (Get-Location).Path
        cd -Path $env:SystemRoot
        Assert-Equal $env:SystemRoot (Get-Location).Path
        Set-Location HKCU:\Software
        cd
        Assert-Equal $HOME (Get-Location).Path 'from another provider'
    }
    finally { Pop-Location }
}

Test-Case 'dotted paths: ... is ..\.., .... is ..\..\.. and so on' {
    Assert-Equal '..\..' (_ps10k_expand_dots '...')
    Assert-Equal '..\..\..' (_ps10k_expand_dots '....')
    Assert-Equal '..\..\..\..' (_ps10k_expand_dots '.....')
    Assert-Equal '..\..\src' (_ps10k_expand_dots '...\src') 'at the start of a path'
    Assert-Equal '../../src' (_ps10k_expand_dots '.../src') 'keeps the typed separator'
    foreach ($same in '..', '.', 'a...', '...x', '.\...') { Assert-Equal $same (_ps10k_expand_dots $same) "$same unchanged" }
    Assert-Equal 'cd ..\..' (_ps10k_expand_dots_line 'cd ...')
    Assert-Equal 'cp a ..\..\..\b; ls ..\..' (_ps10k_expand_dots_line 'cp a ....\b; ls ...') 'every command of the line'
    Assert-Equal '...' (_ps10k_expand_dots_line '...') 'the ... command itself stays'
    Assert-Equal "echo '...' `"...`"" (_ps10k_expand_dots_line "echo '...' `"...`"") 'quoted text stays'
    Assert-Equal 'git log -n 3' (_ps10k_expand_dots_line 'git log -n 3') 'lines without dots stay'
    $deep = Join-Path $work 'dots\a\b\c'
    New-Item -ItemType Directory -Path $deep -Force | Out-Null
    Push-Location -LiteralPath $deep
    try {
        cd ...
        Assert-Equal (Join-Path $work 'dots\a') (Get-Location).Path 'cd ... goes up two folders'
        Set-Location -LiteralPath $deep
        cd ....\a\b
        Assert-Equal (Join-Path $work 'dots\a\b') (Get-Location).Path 'cd ....\a\b'
        Set-Location -LiteralPath $deep
        cd -Path ...
        Assert-Equal (Join-Path $work 'dots\a') (Get-Location).Path 'with -Path too'
    }
    finally { Pop-Location }
}

Test-Case 'colors reject unknown values and strip escape sequences' {
    Assert-Equal "$([char]27)[38;5;12m" (_ps10k_fg 'BrightBlue') 'names ignore case'
    Assert-Equal '' (_ps10k_fg 'no-such-color')
    Assert-Equal '' (_ps10k_fg '#12345')
    Assert-Equal '' (_ps10k_bg '')
    Assert-Equal 'abc' (_ps10k_strip_ansi "$([char]27)[1ma$([char]27)[38;2;1;2;3mb$([char]27)]9;9;`"x`"$([char]27)\c")
    Assert-Equal '' (_ps10k_strip_ansi $null)
    Assert-Equal ([string][char]0x276F) (_ps10k_u 0x276F)
}

Test-Case 'config defaults and ~/.p10k.ps1 overrides' {
    $defaults = _ps10k_default_config
    Assert-Equal 'rainbow' $defaults.Style
    Assert-Equal 'os_icon dir git' ($defaults.LeftSegments -join ' ')
    $savedPath = $env:PS10K_CONFIG; $savedConfig = $global:P10K
    try {
        $path = Join-Path $work 'override.p10k.ps1'
        Set-Content -LiteralPath $path -Value "`$P10K.Style = 'pure'; `$P10K.TimeFormat = 'HH:mm'"
        $env:PS10K_CONFIG = $path
        Assert-Equal $path (_ps10k_config_path)
        _ps10k_load_config
        Assert-Equal 'pure' $global:P10K.Style
        Assert-Equal 'HH:mm' $global:P10K.TimeFormat
        Assert-Equal 'nerdfont' $global:P10K.Mode 'untouched keys keep their default'
        Set-Content -LiteralPath $path -Value 'throw "broken config"'
        $warnings = @(_ps10k_load_config 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        Assert-True ("$warnings" -match 'broken config') 'a broken config is reported'
        Assert-Equal 'rainbow' $global:P10K.Style 'and the defaults stay usable'
        Remove-Item Env:PS10K_CONFIG
        Assert-Equal (Join-Path $HOME '.p10k.ps1') (_ps10k_config_path)
    }
    finally { $env:PS10K_CONFIG = $savedPath; $global:P10K = $savedConfig }
}

Test-Case 'custom plugins and themes win over bundled ones' {
    $custom = Join-Path $work 'custom'
    foreach ($dir in 'plugins\mine', 'plugins\git', 'plugins\empty', 'themes') { New-Item -ItemType Directory -Path (Join-Path $custom $dir) -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $custom 'plugins\mine\mine.plugin.ps1') -Value '# mine'
    Set-Content -LiteralPath (Join-Path $custom 'plugins\git\git.plugin.ps1') -Value '# my git'
    Set-Content -LiteralPath (Join-Path $custom 'themes\mytheme.theme.ps1') -Value '# theme'
    $saved = $global:PS10K_CUSTOM
    try {
        $global:PS10K_CUSTOM = $custom
        Assert-Equal (Join-Path $custom 'plugins\mine\mine.plugin.ps1') (_ps10k_find_plugin 'mine')
        Assert-Equal (Join-Path $custom 'plugins\git\git.plugin.ps1') (_ps10k_find_plugin 'git') 'custom wins'
        Assert-Equal (Join-Path $root 'plugins\z\z.plugin.ps1') (_ps10k_find_plugin 'z')
        Assert-True ($null -eq (_ps10k_find_plugin 'no-such-plugin'))
        Assert-Equal (Join-Path $custom 'themes\mytheme.theme.ps1') (_ps10k_find_theme 'mytheme')
        Assert-Equal (Join-Path $root 'themes\powerlevel10k.theme.ps1') (_ps10k_find_theme 'powerlevel10k')
        $plugins = _ps10k_list_dir_names 'plugins'
        foreach ($name in 'mine', 'git', 'z', 'vi-mode') { Assert-True ($plugins -contains $name) "plugin $name listed" }
        Assert-True ($plugins -notcontains 'empty') 'folders without a plugin file are skipped'
        Assert-Equal 1 @($plugins | Where-Object { $_ -eq 'git' }).Count 'listed once'
        Assert-Equal 'minimal mytheme powerlevel10k' ((_ps10k_list_dir_names 'themes') -join ' ')
    }
    finally { $global:PS10K_CUSTOM = $saved }
}

Test-Case 'icons and separators follow the glyph mode' {
    $saved = $global:P10K
    try {
        $global:P10K = _ps10k_default_config
        Assert-Equal ([string][char]0x276F) (_ps10k_icon 'prompt')
        Assert-Equal '' (_ps10k_icon 'no-such-icon')
        Assert-Equal '' (_ps10k_icon '')
        $global:P10K.Icons['branch'] = 'B'
        Assert-Equal 'B' (_ps10k_icon 'branch') 'user overrides win'
        Assert-Equal ([string][char]0xE0B0) (_ps10k_separators).L 'sharp heads'
        $global:P10K.Heads = 'round'
        Assert-Equal ([string][char]0xE0B4) (_ps10k_separators).L
        $global:P10K.Heads = 'bogus'
        Assert-Equal ([string][char]0xE0B0) (_ps10k_separators).L 'unknown heads fall back to sharp'
        $global:P10K.Mode = 'unicode'
        Assert-Equal 'unicode' (_ps10k_glyph_class)
        Assert-Equal '' (_ps10k_separators).L 'no powerline glyphs without a Nerd Font'
        $global:P10K.Mode = 'ascii'
        Assert-Equal '>' (_ps10k_icon 'prompt')
        Assert-Equal 'ascii' (_ps10k_glyph_class)
        $global:P10K.Mode = 'bogus'
        Assert-Equal ([string][char]0x276F) (_ps10k_icon 'prompt') 'unknown modes fall back to nerdfont'
    }
    finally { $global:P10K = $saved }
}

Test-Case 'hooks run in order, chpwd only after a directory change, failures warn' {
    $counts = @{}
    foreach ($type in 'precmd', 'chpwd', 'preexec') { $counts[$type] = $global:PS10K_HOOKS[$type].Count }
    $global:_test_hooks = New-Object System.Collections.ArrayList
    try {
        Add-PS10kHook -Type chpwd -Action { param($ctx) [void]$global:_test_hooks.Add("chpwd:$($ctx.Tag)") }
        Add-PS10kHook -Type precmd -Action { param($ctx) [void]$global:_test_hooks.Add("precmd:$($ctx.Tag)") }
        Add-PS10kHook -Type preexec -Action { [void]$global:_test_hooks.Add('preexec') }
        $global:_ps10k_last_location = $null
        _ps10k_hooks_before_prompt @{ Tag = 1 } 3>$null
        _ps10k_hooks_before_prompt @{ Tag = 2 } 3>$null
        Assert-Equal 'chpwd:1 precmd:1 precmd:2' (@($global:_test_hooks) -join ' ') 'chpwd once, before precmd'
        _ps10k_run_hooks -Type preexec 3>$null
        Assert-Equal 'preexec' $global:_test_hooks[-1]
        Add-PS10kHook -Type precmd -Action { throw 'hook exploded' }
        $warnings = @(_ps10k_run_hooks -Type precmd -Context @{ Tag = 3 } 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        Assert-True ("$warnings" -match 'precmd hook failed: hook exploded')
        Assert-True ($global:_test_hooks -contains 'precmd:3') 'other hooks still ran'
        $threw = $false
        try { Add-PS10kHook -Type bogus -Action { } } catch { $threw = $true }
        Assert-True $threw 'unknown hook types are rejected'
    }
    finally {
        foreach ($type in $counts.Keys) {
            $list = $global:PS10K_HOOKS[$type]
            if ($list.Count -gt $counts[$type]) { $list.RemoveRange($counts[$type], $list.Count - $counts[$type]) }
        }
        Remove-Variable -Name _test_hooks -Scope Global -ErrorAction SilentlyContinue
    }
}

Test-Case 'load errors are recorded and shown as warnings' {
    $before = $global:PS10K_LOAD_ERRORS.Count
    $warnings = @(_ps10k_load_error 'test problem' 3>&1)
    Assert-Equal ($before + 1) $global:PS10K_LOAD_ERRORS.Count
    Assert-Equal 'test problem' $global:PS10K_LOAD_ERRORS[-1]
    Assert-True ("$warnings" -match 'powershell10k: test problem')
    $global:PS10K_LOAD_ERRORS.RemoveAt($global:PS10K_LOAD_ERRORS.Count - 1)
}

Test-Case 'PSReadLine helpers work outside a running prompt' {
    Assert-True (_ps10k_line_complete) 'an empty buffer is complete'
    Assert-True (-not (_ps10k_rl_clear_emphasis))
    $rl = _ps10k_rl_internals
    if ($rl) {
        $end = _ps10k_rl_end_point $rl
        Assert-True ($end.X -is [int] -and $end.Y -is [int]) 'end point has coordinates'
    }
    _ps10k_bind_accept_line
    $enter = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq 'Enter' } | Select-Object -First 1
    Assert-Equal 'PS10kAcceptLine' $enter.Function
    Assert-Equal 'got x' (_ps10k_with_readline_input { 'got x' })
}

Test-Case 'ps10k and p10k commands' {
    Assert-Equal ((Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim()) (ps10k version)
    Assert-True ((ps10k) -match 'Usage: ps10k') 'help'
    Assert-True ((ps10k nonsense) -match 'Usage: ps10k') 'unknown commands show help'
    $plugins = @(ps10k plugins)
    Assert-True ($plugins -contains '* git') 'enabled plugins are marked'
    Assert-True ($plugins -contains '  vi-mode') 'others are not'
    $themes = @(ps10k themes)
    Assert-True ($themes -contains '* powerlevel10k')
    Assert-True ($themes -contains '  minimal')
    Assert-True ((p10k) -match 'Usage: p10k')
    $segments = @(p10k segments)
    Assert-True ($segments -contains 'left  dir')
    Assert-True ($segments -contains 'right time')
    Assert-True (-not (_ps10k_font_installed 'definitely-no-font-ps10k'))
    $doctor = @(ps10k doctor 6>&1) -join "`n"
    Assert-True ($doctor -match 'powershell10k') 'doctor prints a report'
    Assert-True ($doctor -match 'PSReadLine')
}

Test-Case 'p10k edit opens the config in $env:EDITOR' {
    $savedEditor = $env:EDITOR; $savedPath = $env:PS10K_CONFIG
    try {
        $env:PS10K_CONFIG = Join-Path $work 'missing.p10k.ps1'
        Assert-True ((p10k edit 6>&1) -match 'p10k configure') 'no config yet'
        $env:PS10K_CONFIG = Join-Path $work 'edit.p10k.ps1'
        Set-Content -LiteralPath $env:PS10K_CONFIG -Value '# config'
        function global:Test-FakeEditor { $global:_test_edited = $args[0] }
        $env:EDITOR = 'Test-FakeEditor'
        p10k edit
        Assert-Equal $env:PS10K_CONFIG $global:_test_edited
    }
    finally {
        $env:EDITOR = $savedEditor; $env:PS10K_CONFIG = $savedPath
        Remove-Item Function:\Test-FakeEditor, Variable:\_test_edited -ErrorAction SilentlyContinue
    }
}
