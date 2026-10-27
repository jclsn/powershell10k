<#
.SYNOPSIS
    Dependency-free test runner for powershell10k.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
#>
$ErrorActionPreference = 'Stop'
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

Write-Host 'static checks'

Test-Case 'all scripts parse and are ASCII-only' {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\\.git\\' }) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "$($file.Name): $($errors[0].Message)" }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw "$($file.Name) contains non-ASCII bytes" }
    }
}

Write-Host 'framework'

$env:PS10K_HOME = $root
$env:PS10K_CONFIG = Join-Path $work 'p10k.ps1'
$env:PS10K_Z_DATA = Join-Path $work 'z'
$env:PS10K_DISABLE_WIZARD = '1'
Import-Module PSReadLine -ErrorAction SilentlyContinue
$global:PS10K_PLUGINS = @('git', 'z', 'aliases', 'autosuggestions', 'syntax-highlighting', 'extract', 'web-search', 'copypath')
$global:PS10K_THEME = 'powerlevel10k'

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
    Assert-Equal 1 (_ps10k_width "$([char]27)]9;9;`"C:\`"$([char]27)\x")
}

Test-Case 'colors accept indexes, names and hex' {
    Assert-Equal "$([char]27)[38;5;4m" (_ps10k_fg 4)
    Assert-Equal "$([char]27)[48;5;1m" (_ps10k_bg 'red')
    Assert-Equal "$([char]27)[38;2;255;0;16m" (_ps10k_fg '#ff0010')
    Assert-Equal '' (_ps10k_fg $null)
}

Test-Case 'git porcelain v2 parser' {
    $s = _ps10k_parse_git_status @(
        '# branch.oid 1234567890abcdef', '# branch.head feature/x', '# branch.upstream origin/feature/x',
        '# branch.ab +2 -3', '# stash 4',
        '1 M. N... 100644 100644 100644 a b file1', '1 .M N... 100644 100644 100644 a b file2',
        '1 MM N... 100644 100644 100644 a b file3', 'u UU N... 1 2 3 4 a b c conflict', '? new1', '? new2'
    )
    Assert-Equal 'feature/x' $s.Branch
    Assert-Equal 2 $s.Ahead; Assert-Equal 3 $s.Behind; Assert-Equal 4 $s.Stash
    Assert-Equal 2 $s.Staged; Assert-Equal 2 $s.Unstaged
    Assert-Equal 1 $s.Conflicted; Assert-Equal 2 $s.Untracked
}

Test-Case 'duration formatting' {
    Assert-Equal '4s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 0)
    Assert-Equal '4.70s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 2)
    Assert-Equal '1m 5s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(65)) 0)
    Assert-Equal '1h 0m 1s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(3601)) 0)
}

Test-Case 'long paths are shortened in the middle' {
    $long = 'C:\Users\someone\projects\.config\very-long-directory-name\leaf'
    Assert-Equal 'C:\U\s\p\.config\very-long-directory-name\leaf' ((_ps10k_shorten_path $long 46 '\') -join '\')
    Assert-Equal 'C:\U\s\p\.c\v\leaf' ((_ps10k_shorten_path $long 10 '\') -join '\')
    $parts = _ps10k_shorten_path 'C:\short' 30 '\'
    Assert-Equal 'C:\short' ($parts -join '\')
}

Test-Case 'git segment reports branch and changes' {
    $repo = Join-Path $work 'repo'
    New-Item -ItemType Directory -Path $repo | Out-Null
    git -C $repo init -q -b trunk 2>$null
    git -C $repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>$null
    Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'a'
    git -C $repo add tracked.txt 2>$null
    git -C $repo -c user.name=t -c user.email=t@t commit -q -m add 2>$null
    Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'b'
    Set-Content -LiteralPath (Join-Path $repo 'new.txt') -Value 'c'
    Push-Location $repo
    try {
        $ctx = @{ Location = $executionContext.SessionState.Path.CurrentLocation }
        $seg = & $global:PS10K_SEGMENTS['git'] $ctx
        Assert-Equal 'trunk !1 ?1' $seg.Text
        Assert-Equal 'modified' $seg.State
    }
    finally { Pop-Location }
}

Test-Case 'prompt renders in every style and layout' {
    foreach ($style in 'rainbow', 'classic', 'lean', 'pure') {
        foreach ($multi in $true, $false) {
            $P10K.Style = $style; $P10K.MultiLine = $multi
            $text = prompt
            Assert-True ($text -match 'tests|powershell10k') "style $style missing directory"
            Assert-True ($text -notmatch '^PS ') "style $style fell back to the plain prompt: $($global:_ps10k_state.PromptError)"
        }
    }
    _ps10k_load_config
}

Test-Case 'two-line prompt fills the first line to the terminal width' {
    $left = @(@{ Name = 'dir'; Icon = 'folder'; Text = 'C:\x' })
    $right = @(@{ Name = 'time'; Icon = 'time'; Text = '12:00:00' })
    foreach ($gap in 'none', 'dot', 'line') {
        $P10K.Gap = $gap
        $text = _ps10k_render_prompt -Left $left -Right $right -Width 80
        $line1 = ($text -split "`n")[1]
        Assert-Equal 79 (_ps10k_width $line1) "gap $gap"
    }
    _ps10k_load_config
}

Test-Case 'status segment shows the exit code' {
    $seg = & $global:PS10K_SEGMENTS['status'] @{ Success = $false; ExitCode = 2 }
    Assert-Equal '2' $seg.Text
    Assert-Equal 'error' $seg.State
    Assert-True ($null -eq (& $global:PS10K_SEGMENTS['status'] @{ Success = $true; ExitCode = 0 }))
}

Test-Case 'prompt preserves LASTEXITCODE' {
    $global:LASTEXITCODE = 7
    $null = prompt
    Assert-Equal 7 $global:LASTEXITCODE
}

Test-Case 'z ranks visited directories' {
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\beta\project'
    $found = _ps10k_z_matches -Terms @('project')
    Assert-Equal 'C:\alpha\project' $found[0].Path
    Assert-Equal 1 @(_ps10k_z_matches -Terms @('beta')).Count
}

Test-Case 'syntax highlighting detects unknown commands' {
    if (-not (Get-Command _ps10k_hl_line_valid -ErrorAction SilentlyContinue)) { throw 'plugin not loaded (PSReadLine missing?)' }
    Assert-True (_ps10k_hl_line_valid 'Get-ChildItem | Select-Object -First 1')
    Assert-True (-not (_ps10k_hl_line_valid 'definitely-not-a-command-ps10k'))
    Assert-True (_ps10k_hl_line_valid '')
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
        Assert-Equal 'HistorySearchBackward' $commandKeys[0].Function
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

Test-Case 'configure writes a config that loads back' {
    $answers = [ordered]@{ Mode = 'unicode'; Style = 'lean'; MultiLine = $false; RightSegments = @('status', 'time'); TransientPrompt = $true }
    Set-Content -LiteralPath $env:PS10K_CONFIG -Value (_ps10k_wizard_config_text $answers) -Encoding UTF8
    _ps10k_load_config
    Assert-Equal 'lean' $P10K.Style
    Assert-Equal 'unicode' $P10K.Mode
    Assert-Equal $false $P10K.MultiLine
    Assert-Equal 'status time' "$($P10K.RightSegments)"
    Remove-Item -LiteralPath $env:PS10K_CONFIG
    _ps10k_load_config
}

Write-Host 'installer'

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

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
$color = if ($script:Failed -eq 0) { 'Green' } else { 'Red' }
Write-Host "$($script:Passed) passed, $($script:Failed) failed" -ForegroundColor $color
exit ([int]($script:Failed -gt 0))
