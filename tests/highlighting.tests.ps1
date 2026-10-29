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
            Assert-True (_ps10k_hl_line_valid $line) "$line should be valid"
        }
        foreach ($line in '.\notes.md', '.\missing.bat', 'run.ps1') {
            Assert-True (-not (_ps10k_hl_line_valid $line)) "$line should be invalid"
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
    [void](_ps10k_hl_line_valid '.\no-such-script-ps10k')
    [void](_ps10k_hl_line_valid 'no-such-command-ps10k')
    Assert-Equal $before $global:Error.Count
}

Test-Case 'syntax highlighting detects unknown commands' {
    if (-not (Get-Command _ps10k_hl_line_valid -ErrorAction SilentlyContinue)) { throw 'plugin not loaded (PSReadLine missing?)' }
    Assert-True (_ps10k_hl_line_valid 'Get-ChildItem | Select-Object -First 1')
    Assert-True (-not (_ps10k_hl_line_valid 'definitely-not-a-command-ps10k'))
    Assert-True (_ps10k_hl_line_valid '')
}
