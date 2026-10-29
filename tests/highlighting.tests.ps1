# The syntax-highlighting plugin.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'highlighting accepts scripts and executables, not documents' {
    $dir = Join-Path $work 'exec'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($name in 'run.ps1', 'build.bat', 'build.cmd', 'tool.exe', 'notes.md') {
        Set-Content -LiteralPath (Join-Path $dir $name) -Value 'x'
    }
    Push-Location $dir
    try {
        $global:PS10K_HL.Cache = @{}
        foreach ($line in '.\run.ps1', '.\run', '& .\build.bat -x', '.\build.cmd', '.\tool.exe', "$dir\build.bat", 'whoami') {
            Assert-True ((_ps10k_hl_analyze $line).Valid) "$line should be valid"
        }
        foreach ($line in '.\notes.md', '.\missing.bat', 'run.ps1') {
            Assert-True (-not ((_ps10k_hl_analyze $line).Valid)) "$line should be invalid"
        }
    }
    finally { Pop-Location }
}

Test-Case 'existing paths and their beginnings are underlined' {
    $dir = Join-Path $work 'paths'
    New-Item -ItemType Directory -Path (Join-Path $dir 'Workspace\Docker') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'notes.txt') -Value 'x'
    Push-Location $dir
    try {
        $global:PS10K_HL.Cache = @{}
        foreach ($value in 'Wo', 'Workspace', 'Workspace\', 'Workspace\Docker\', 'Workspace/Do', '.\notes.txt', 'note', "$dir\Workspace") {
            Assert-True (_ps10k_hl_path_like $value) "$value should count as a path"
        }
        foreach ($value in 'Wox', 'notes.txt\', 'Workspace\Nope', 'W*', '') {
            Assert-True (-not (_ps10k_hl_path_like $value)) "$value should not count as a path"
        }
        Assert-True (_ps10k_hl_analyze 'ls Workspace\Docker\').Bare
        Assert-True (-not (_ps10k_hl_analyze 'ls Wox').Bare)
        Assert-True (-not (_ps10k_hl_analyze 'cp Workspace nope').Bare) 'not all arguments are paths'
        Assert-True (_ps10k_hl_analyze "ls 'Workspace'").Quoted
        Assert-True (-not (_ps10k_hl_analyze 'ls -Force').Bare) 'parameters are not arguments'
        $esc = [char]27
        [void](_ps10k_hl_update 'ls Wo')
        Assert-Equal "$esc[4m$esc[39m" (Get-PSReadLineOption).DefaultTokenColor 'underlined'
        [void](_ps10k_hl_update 'ls Wox')
        Assert-Equal "$esc[24m$esc[39m" (Get-PSReadLineOption).DefaultTokenColor 'not underlined'
        [void](_ps10k_hl_update 'ls Wo')
        _ps10k_run_hooks -Type preexec
        Assert-Equal "$esc[24m$esc[39m" (Get-PSReadLineOption).DefaultTokenColor 'no underline when the command runs'
        Assert-True (Get-PSReadLineOption).ParameterColor.StartsWith("$esc[24") 'other colors switch underline off'
        [void](_ps10k_hl_update 'ls Wo')
        Assert-True $global:PS10K_HL.Underlined
        _ps10k_hl_clear_padding 'ls Workspace\Docker\'
        [void](_ps10k_hl_update 'ls Wox')
        Assert-True (-not $global:PS10K_HL.Underlined)
    }
    finally { Pop-Location; [void](_ps10k_hl_update '') }
}

Test-Case 'keys that shorten the line are wrapped for highlighting' {
    $bound = @{}
    foreach ($k in Get-PSReadLineKeyHandler -Bound) { if (-not $bound.ContainsKey($k.Key)) { $bound[$k.Key] = $k.Function } }
    foreach ($key in 'UpArrow', 'DownArrow', 'Ctrl+w', 'Ctrl+u', 'Ctrl+z') {
        if ($bound.ContainsKey($key)) { Assert-True ($bound[$key] -like 'PS10k*') "$key is wrapped, got $($bound[$key])" }
    }
    Assert-True (Get-Command _ps10k_rl_clear_emphasis) 'history emphasis can be switched off'
    Assert-True (-not (_ps10k_rl_clear_emphasis)) 'no emphasis outside a history search'
}

Test-Case 'highlighting lookups do not fill $Error' {
    $before = $global:Error.Count
    [void]((_ps10k_hl_analyze '.\no-such-script-ps10k').Valid)
    [void]((_ps10k_hl_analyze 'no-such-command-ps10k').Valid)
    Assert-Equal $before $global:Error.Count
}

Test-Case 'syntax highlighting detects unknown commands' {
    if (-not (Get-Command _ps10k_hl_analyze -ErrorAction SilentlyContinue)) { throw 'plugin not loaded (PSReadLine missing?)' }
    Assert-True ((_ps10k_hl_analyze 'Get-ChildItem | Select-Object -First 1').Valid)
    Assert-True (-not ((_ps10k_hl_analyze 'definitely-not-a-command-ps10k').Valid))
    Assert-True ((_ps10k_hl_analyze '').Valid)
}

Test-Case 'command lookups are cached and documents are not executables' {
    $global:PS10K_HL.Cache = @{}
    Assert-True (_ps10k_hl_command_valid 'Get-ChildItem')
    Assert-True $global:PS10K_HL.Cache.ContainsKey('Get-ChildItem') 'cached'
    $global:PS10K_HL.Cache['made-up-ps10k'] = $true
    Assert-True (_ps10k_hl_command_valid 'made-up-ps10k') 'the cache is used'
    Assert-True (_ps10k_hl_executable (Get-Command Get-ChildItem)) 'cmdlets'
    Assert-True (_ps10k_hl_executable ([pscustomobject]@{ CommandType = 'Application'; Source = 'C:\x\tool.EXE' })) 'case-insensitive extensions'
    Assert-True (-not (_ps10k_hl_executable ([pscustomobject]@{ CommandType = 'Application'; Source = 'C:\x\notes.md' })))
    $global:PS10K_HL.Cache = @{}
}

Test-Case 'colors are only set when they change' {
    $esc = [char]27
    $global:PS10K_HL.Current = $null
    Assert-True (_ps10k_hl_apply $true $false $false) 'first call sets the colors'
    Assert-True (-not (_ps10k_hl_apply $true $false $false)) 'unchanged: nothing to do'
    Assert-True (_ps10k_hl_apply $false $false $true)
    Assert-Equal "$esc[24m$($global:PS10K_HL.Invalid)" (Get-PSReadLineOption).CommandColor 'invalid command in red'
    Assert-Equal "$esc[4m$($global:PS10K_HL.String)" (Get-PSReadLineOption).StringColor 'quoted paths underlined'
    [void](_ps10k_hl_update '')
    $buffer = _ps10k_hl_buffer
    Assert-Equal '' $buffer.Line
    Assert-Equal 0 $buffer.Cursor
    _ps10k_hl_refresh '' $true
}

Test-Case 'completion colors for folders, executables, archives and the rest' {
    function New-Result($Text, $Type) { New-Object System.Management.Automation.CompletionResult($Text, $Text, $Type, $Text) }
    $folder = _ps10k_hl_folder_color
    Assert-Equal $folder (_ps10k_hl_completion_color (New-Result 'src' 'ProviderContainer') $folder)
    Assert-Equal $global:PS10K_HL.Valid (_ps10k_hl_completion_color (New-Result 'run.ps1' 'ProviderItem') $folder)
    Assert-Equal $global:PS10K_HL.Invalid (_ps10k_hl_completion_color (New-Result 'pack.tar.gz' 'ProviderItem') $folder) 'by the last extension'
    Assert-True ($null -eq (_ps10k_hl_completion_color (New-Result 'notes.txt' 'ProviderItem') $folder))
    Assert-True ($null -eq (_ps10k_hl_completion_color (New-Result 'Makefile' 'ProviderItem') $folder)) 'no extension'
    Assert-True ($null -eq (_ps10k_hl_completion_color (New-Result 'Get-Item' 'Command') $folder)) 'only files and folders'
    $mixed = New-Object System.Management.Automation.CommandCompletion(
        [System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]]@((New-Result "'a b'" 'ProviderContainer'), (New-Result 'c' 'ProviderContainer')), -1, 0, 0)
    _ps10k_hl_color_completions $mixed
    Assert-True (-not $mixed.CompletionMatches[1].ListItemText.Contains([char]27)) 'no common prefix: left uncolored'
    $saved = $global:PS10K_HL_COMPLETION
    try {
        $global:PS10K_HL_COMPLETION = $false
        $plain = New-Object System.Management.Automation.CommandCompletion(
            [System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]]@((New-Result '.\a' 'ProviderContainer'), (New-Result '.\b' 'ProviderContainer')), -1, 0, 0)
        _ps10k_hl_color_completions $plain
        Assert-True (-not $plain.CompletionMatches[0].ListItemText.Contains([char]27)) 'switched off'
    }
    finally { $global:PS10K_HL_COMPLETION = $saved }
}
