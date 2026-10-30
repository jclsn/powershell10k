# The z and vi-mode plugins.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'z ranks visited directories' {
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\beta\project'
    $found = _ps10k_z_matches -Terms @('project')
    Assert-Equal 'C:\alpha\project' $found[0].Path
    Assert-Equal 1 @(_ps10k_z_matches -Terms @('beta')).Count
}

Test-Case 'vi-mode switches PSReadLine and redraws the prompt char' {
    if (-not (Get-Module PSReadLine)) { throw 'PSReadLine missing' }
    $plugins = $global:PS10K_PLUGINS
    try {
        $global:PS10K_PLUGINS = @('syntax-highlighting', 'vi-mode')
        $warnings = . (Join-Path $root 'powershell10k.ps1') 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        if ($warnings) { throw "warnings: $($warnings -join '; ')" }
        Assert-Equal 'Vi' (Get-PSReadLineOption).EditMode
        $commandKeys = @(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq '<k>' })
        Assert-Equal 'PS10kHistorySearchBackward' $commandKeys[0].Function 'k searches history (wrapped by syntax-highlighting)'
        $P10K.MultiLine = $true
        [void](prompt)
        $global:_ps10k_state.ViMode = 'Command'
        $global:_ps10k_state.ViRedraw = $true
        $redrawn = prompt
        Assert-True $redrawn.StartsWith($global:_ps10k_state.LastPrompt.Head) 'redraw changed the prompt body'
        Assert-True $redrawn.Contains((_ps10k_icon 'prompt_vicmd')) 'command mode prompt char missing'
        Assert-True (-not (prompt).Contains((_ps10k_icon 'prompt_vicmd'))) 'a new prompt starts in insert mode'
    }
    finally {
        $global:PS10K_PLUGINS = $plugins
        . (Join-Path $root 'powershell10k.ps1') 3>$null
    }
    Assert-Equal 'Windows' (Get-PSReadLineOption).EditMode 'reload without vi-mode'
}

# Captures what $Body writes with [Console]::Write.
function Get-ConsoleOutput([scriptblock]$Body) {
    $writer = New-Object IO.StringWriter
    $saved = [Console]::Out
    [Console]::SetOut($writer)
    try { & $Body } finally { [Console]::SetOut($saved) }
    $writer.ToString()
}

# Replaces a command with a recording function for the length of $Body.
function Use-TestMock([string]$Name, [scriptblock]$Body) {
    $global:_test_calls = New-Object System.Collections.ArrayList
    Set-Item -Path "Function:global:$Name" -Value { [void]$global:_test_calls.Add(@($args) + @($input)) }
    try { & $Body } finally { Remove-Item -LiteralPath "Function:\$Name" -ErrorAction SilentlyContinue }
}

Test-Case 'vi-mode cursor shapes and prompt text' {
    $esc = [char]27
    Assert-Equal "$esc[5 q" (Get-ConsoleOutput { _ps10k_vi_cursor 'Insert' }) 'blinking bar'
    Assert-Equal "$esc[2 q" (Get-ConsoleOutput { _ps10k_vi_cursor 'Command' }) 'block'
    Assert-Equal "$esc[0 q" (Get-ConsoleOutput { _ps10k_vi_cursor 'Default' }) 'terminal default for programs'
    $saved = $global:PS10K_VI_CURSOR
    try {
        $global:PS10K_VI_CURSOR = $false
        Assert-Equal '' (Get-ConsoleOutput { _ps10k_vi_cursor 'Insert' }) 'cursor left alone'
    }
    finally { $global:PS10K_VI_CURSOR = $saved }
    _ps10k_vi_prompt_text 'Command'
    Assert-Equal "$(_ps10k_icon 'prompt_vicmd') " ((Get-PSReadLineOption).PromptText -join '')
    _ps10k_vi_prompt_text 'Insert'
    Assert-Equal "$(_ps10k_icon 'prompt') " ((Get-PSReadLineOption).PromptText -join '')
}

Test-Case 'vi-mode switches cursor, state and prompt text on mode changes' {
    $state = $global:_ps10k_state
    $savedPrompt = $state.LastPrompt
    try {
        $state.LastPrompt = $null
        # Colors already right for the empty line: no redraw, which needs a running prompt.
        [void](_ps10k_hl_update '')
        $global:PS10K_VI_MODE = 'Insert'
        $out = Get-ConsoleOutput { _ps10k_vi_mode_changed 'Command' }
        Assert-True ($out.StartsWith("$([char]27)[2 q")) 'block cursor'
        Assert-Equal 'Command' $global:PS10K_VI_MODE
        Assert-Equal 'Command' $state.ViMode
        $out = Get-ConsoleOutput { _ps10k_vi_mode_changed 'Command' }
        Assert-Equal "$([char]27)[2 q" $out 'same mode: only the cursor'
        [void](Get-ConsoleOutput { _ps10k_vi_mode_changed 'Insert' })
        Assert-Equal 'Insert' $global:PS10K_VI_MODE
    }
    finally { $state.LastPrompt = $savedPrompt; $state.ViMode = 'Insert'; $global:PS10K_VI_MODE = 'Insert' }
}

Test-Case 'z keeps, ages, removes and jumps to directories' {
    $saved = $env:PS10K_Z_DATA
    $env:PS10K_Z_DATA = Join-Path $work 'z-test'
    try {
        # Not under $work\z: that is the harness's z data file.
        $a = Join-Path $work 'zdirs\alpha\project'; $b = Join-Path $work 'zdirs\beta\project'
        New-Item -ItemType Directory -Path $a, $b -Force | Out-Null
        Assert-Equal 0 (_ps10k_z_load).Count 'no data yet'
        _ps10k_z_add $HOME
        Assert-Equal 0 (_ps10k_z_load).Count 'home is not recorded'
        _ps10k_z_add $a; _ps10k_z_add $a; _ps10k_z_add $b
        $entries = _ps10k_z_load
        Assert-Equal 2 $entries[$a].Rank
        Assert-True ($entries[$a].Time -le (_ps10k_z_now))
        $now = _ps10k_z_now
        $entry = @{ Rank = 4.0; Time = $now }
        Assert-Equal 16 (_ps10k_z_frecency $entry $now) 'within the hour'
        Assert-Equal 8 (_ps10k_z_frecency $entry ($now + 7200)) 'within the day'
        Assert-Equal 2 (_ps10k_z_frecency $entry ($now + 172800)) 'within the week'
        Assert-Equal 1 (_ps10k_z_frecency $entry ($now + 1209600)) 'older'
        Assert-Equal $a (_ps10k_z_matches -Terms @('alpha', 'proj'))[0].Path 'terms match in order'
        Assert-Equal 0 @(_ps10k_z_matches -Terms @('proj', 'alpha')).Count
        Assert-Equal 1 @(_ps10k_z_matches -Terms @('project') -Under (Join-Path $work 'zdirs\beta')).Count 'restricted to a folder'
        Push-Location
        try {
            z beta
            Assert-Equal $b (Get-Location).Path 'z jumps to the best match'
            z -x
            Assert-True (-not (_ps10k_z_load).ContainsKey($b)) 'z -x forgets the current folder'
            $warnings = @(z no-such-place 3>&1)
            Assert-True ("$warnings" -match 'no match') 'unknown places warn'
            z $a
            Assert-Equal $a (Get-Location).Path 'an existing path works without data'
            Assert-True ("$(z -l 6>&1 | Out-String)" -match 'alpha') 'z -l lists matches'
        }
        finally { Pop-Location }
        $line = 'z alph'
        $completions = @((TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches)
        Assert-True (@($completions | Where-Object { (_ps10k_strip_ansi $_.CompletionText) -eq $a }).Count -eq 1) 'z completes known folders'
        $global:PS10K_Z_MAX_SCORE = 3
        _ps10k_z_add $a
        Assert-True ((_ps10k_z_load)[$a].Rank -lt 4) 'ranks age once the total gets too high'
    }
    finally { $env:PS10K_Z_DATA = $saved; $global:PS10K_Z_MAX_SCORE = 9000 }
}

Test-Case 'aliases plugin: navigation and file helpers' {
    Push-Location
    try {
        $deep = Join-Path $work 'nav\a\b\c\d'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        Set-Location -LiteralPath $deep; ..
        Assert-Equal (Join-Path $work 'nav\a\b\c') (Get-Location).Path
        Set-Location -LiteralPath $deep; ...
        Assert-Equal (Join-Path $work 'nav\a\b') (Get-Location).Path
        Set-Location -LiteralPath $deep; ....
        Assert-Equal (Join-Path $work 'nav\a') (Get-Location).Path
        Set-Location -LiteralPath $deep; .....
        Assert-Equal (Join-Path $work 'nav') (Get-Location).Path
        take (Join-Path $work 'nav\new\folder')
        Assert-Equal (Join-Path $work 'nav\new\folder') (Get-Location).Path 'take creates and enters'
        Assert-Equal 'take' (Get-Alias mkcd).Definition
        touch 'one.txt', 'two.txt'
        Assert-True ((Test-Path 'one.txt') -and (Test-Path 'two.txt')) 'touch creates files'
        $old = (Get-Item 'one.txt').LastWriteTime = (Get-Date).AddDays(-1)
        touch 'one.txt'
        Assert-True ((Get-Item 'one.txt').LastWriteTime -gt (Get-Date).AddMinutes(-1)) 'touch updates the time'
        Assert-Equal 2 @(l).Count 'l lists files'
        Assert-Equal 0 @(lsd).Count 'lsd lists folders only'
    }
    finally { Pop-Location }
    Assert-True ((which git) -match 'git(\.exe)?$') 'which finds programs'
    Assert-True ((which gst) -match 'Function gst')
    Assert-True ((which mkcd) -match 'mkcd -> take')
    $message = try { which no-such-command-ps10k 2>&1 } catch { "$_" }
    Assert-True ("$message" -match 'not found')
    Assert-True ((path) -contains "$env:SystemRoot\system32" -or @(path).Count -gt 0) 'path splits PATH'
    if (_ps10k_find_exe 'pwsh') { Assert-True (-not (Get-Alias pwsh -ErrorAction Ignore)) 'PowerShell 7 stays pwsh' }
    else { Assert-Equal 'powershell' (Get-Alias pwsh).Definition 'pwsh opens Windows PowerShell' }
    # The fallback grep, whether or not grep.exe is on PATH here.
    Assert-Equal 'b' ('a', 'b' | _ps10k_grep 'b').Line 'grep filters piped strings'
    Push-Location -LiteralPath $root
    try { Assert-True (@(Get-ChildItem | _ps10k_grep 'README').Count -eq 1) 'and piped objects as they are displayed' }
    finally { Pop-Location }
    $file = Join-Path $work 'grep.txt'
    Set-Content -LiteralPath $file -Value 'one', 'two'
    Assert-Equal 'two' (_ps10k_grep 'tw' $file).Line 'and files'
    if (-not (Get-Command grep -CommandType Application -ErrorAction Ignore)) { Assert-Equal '_ps10k_grep' (Get-Alias grep).Definition }
}

Test-Case 'extract unpacks zip archives into a folder of the same name' {
    $source = Join-Path $work 'pack-src'
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'inside.txt') -Value 'hello'
    $zip = Join-Path $work 'pack.zip'
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip -Force
    extract $zip 6>$null
    Assert-Equal 'hello' (Get-Content -LiteralPath (Join-Path $work 'pack\inside.txt'))
    Assert-Equal 'extract' (Get-Alias x).Definition
    $windowsTar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path -LiteralPath $windowsTar) {
        $tar = Join-Path $work 'tarred.tar.gz'
        & $windowsTar -czf $tar -C $source inside.txt
        x $tar 6>$null
        Assert-Equal 'hello' (Get-Content -LiteralPath (Join-Path $work 'tarred\inside.txt')) 'tar.gz via Windows tar.exe'
    }
    $message = try { extract (Join-Path $work 'missing.zip') 2>&1 } catch { "$_" }
    Assert-True ("$message" -match 'not found')
}

Test-Case 'web-search opens the right URL' {
    Use-TestMock 'Start-Process' {
        google powershell splatting
        Assert-Equal 'https://www.google.com/search?q=powershell%20splatting' $global:_test_calls[0][0]
        ddg
        Assert-Equal 'https://duckduckgo.com' $global:_test_calls[1][0] 'no query opens the site'
        $message = try { web_search nowhere x 2>&1 } catch { "$_" }
        Assert-True ("$message" -match 'unknown engine')
    }
    foreach ($engine in $global:PS10K_SEARCH_ENGINES.Keys) { Assert-True (Get-Command $engine -CommandType Function) "$engine command" }
}

Test-Case 'copypath and copyfile put text on the clipboard' {
    $file = Join-Path $work 'clip.txt'
    Set-Content -LiteralPath $file -Value 'clip me' -NoNewline
    Use-TestMock 'Set-Clipboard' {
        copypath $file 6>$null
        Assert-Equal $file "$($global:_test_calls[0][1])" 'absolute path'
        Push-Location -LiteralPath $work
        try { copypath 6>$null } finally { Pop-Location }
        Assert-Equal $work.TrimEnd('\') "$($global:_test_calls[1][1])".TrimEnd('\') 'current folder by default'
        copyfile $file 6>$null
        Assert-Equal 'clip me' "$($global:_test_calls[2][0])" 'file contents'
    }
}
