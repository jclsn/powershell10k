<#
.SYNOPSIS
    Prints what powershell10k needs to know when something does not work.
.DESCRIPTION
    Dot-source it in the tab where the problem shows up, so it sees that
    session's PSReadLine and key bindings:
        . $env:PS10K_HOME\tools\diagnose.ps1
    The report is also saved to ~\ps10k-diagnose.txt. It contains paths and
    version numbers, nothing secret.
#>

& {
    # Taken first, so the checks below do not show up as errors.
    $recentErrors = @($global:Error | Select-Object -First 8)
    $lines = New-Object System.Collections.ArrayList
    function Add-Line([string]$Text) { [void]$lines.Add($Text) }
    function Add-Section([string]$Title) { [void]$lines.Add(''); [void]$lines.Add("== $Title") }
    function Try-Value([scriptblock]$Block) { try { "$(& $Block)" } catch { "<error: $($_.Exception.Message)>" } }
    # Test-Path that copes with empty paths, which odd setups produce (no
    # Documents folder: empty $PROFILE).
    function Test-Exists([string]$Path) { [bool]$Path -and (Test-Path -LiteralPath $Path) }

    Add-Section 'session'
    Add-Line "PowerShell      $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition), host $($Host.Name)"
    Add-Line "OS              $([Environment]::OSVersion.VersionString)"
    Add-Line "language mode   $($ExecutionContext.SessionState.LanguageMode)"
    Add-Line "interactive     $([Environment]::UserInteractive), input redirected $(Try-Value { [Console]::IsInputRedirected })"
    Add-Line "command line    $([Environment]::CommandLine)"
    Add-Line "terminal        WT_SESSION=$([bool]$env:WT_SESSION) TERM_PROGRAM=$env:TERM_PROGRAM"
    Add-Line "output encoding $(Try-Value { [Console]::OutputEncoding.WebName })"
    $docs = [Environment]::GetFolderPath('MyDocuments')
    Add-Line "Documents       $docs$(if ($docs -like '\\*') { '  (network share!)' } elseif ($docs -match 'OneDrive') { '  (OneDrive)' })"
    Add-Line ".NET Framework  release $(Try-Value { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop).Release })"

    Add-Section 'execution policy'
    foreach ($p in Get-ExecutionPolicy -List) { Add-Line ("{0,-15} {1}" -f $p.Scope, $p.ExecutionPolicy) }

    Add-Section 'profile'
    Add-Line "PROFILE         $(if ($PROFILE) { $PROFILE } else { '<none>' }) (exists $(Test-Exists $PROFILE))"
    if (Test-Exists $PROFILE) {
        $text = [IO.File]::ReadAllText($PROFILE)
        $block = [regex]::Match($text, '(?s)# >>> powershell10k >>>.*?# <<< powershell10k <<<')
        if ($block.Success) { foreach ($l in $block.Value -split "`r?`n") { Add-Line "  $l" } }
        else { Add-Line '  no powershell10k block' }
        foreach ($l in $text -split "`r?`n" | Where-Object { $_ -match '(?i)psreadline|oh-my-posh|starship|Import-Module|EditMode' }) {
            Add-Line "  other: $l"
        }
    }

    Add-Section 'powershell10k'
    Add-Line "PS10K_HOME      $env:PS10K_HOME (exists $(if ($env:PS10K_HOME) { Test-Exists $env:PS10K_HOME } else { $false }))"
    if ($env:PS10K_HOME) {
        $version = Join-Path $env:PS10K_HOME 'VERSION'
        if (Test-Exists $version) { Add-Line "version         $((Get-Content -LiteralPath $version -TotalCount 1).Trim())" }
        Add-Line "plugins on disk $(@(Get-ChildItem -LiteralPath (Join-Path $env:PS10K_HOME 'plugins') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ')"
        $blocked = @(Get-ChildItem -LiteralPath $env:PS10K_HOME -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction Ignore })
        Add-Line "blocked files   $($blocked.Count)$(if ($blocked) { ' e.g. ' + $blocked[0].FullName })"
    }
    Add-Line "PS10K_PLUGINS   $(@($global:PS10K_PLUGINS) -join ', ')"
    Add-Line "PS10K_THEME     $global:PS10K_THEME"
    Add-Line "prompt from     $(Try-Value { (Get-Command prompt -ErrorAction Stop).ScriptBlock.File })"
    Add-Line "vi mode var     $global:PS10K_VI_MODE"
    if ($global:PS10K_LOAD_ERRORS) { foreach ($e in $global:PS10K_LOAD_ERRORS) { Add-Line "load error      $e" } }
    else { Add-Line 'load errors     none recorded' }

    Add-Section 'PSReadLine'
    $loaded = Get-Module PSReadLine
    Add-Line "loaded          $(if ($loaded) { "$($loaded.Version) from $($loaded.ModuleBase)" } else { 'NO' })"
    foreach ($m in Get-Module -ListAvailable PSReadLine) {
        $dll = Join-Path $m.ModuleBase 'Microsoft.PowerShell.PSReadLine.dll'
        if (-not (Test-Exists $dll)) { $dll = Join-Path $m.ModuleBase 'Microsoft.PowerShell.PSReadLine2.dll' }
        $zone = [bool](Get-Item -LiteralPath $dll -Stream Zone.Identifier -ErrorAction Ignore)
        Add-Line "available       $($m.Version) in $($m.ModuleBase)$(if ($zone) { '  (BLOCKED: downloaded file)' })"
    }
    Add-Line "PSModulePath"
    foreach ($p in $env:PSModulePath -split ';' | Where-Object { $_ }) { Add-Line "  $p" }
    if ($loaded) {
        $o = Get-PSReadLineOption
        Add-Line "EditMode        $($o.EditMode)"
        Add-Line "ViModeIndicator $(Try-Value { $o.ViModeIndicator })"
        Add-Line "ShowToolTips    $($o.ShowToolTips)"
        Add-Line "Prediction      $(Try-Value { $o.PredictionSource })"
        foreach ($k in Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -in 'Tab', 'Shift+Tab', 'Escape', 'Enter', 'UpArrow', '<k>', '<Enter>' }) {
            Add-Line ("key {0,-11} {1}" -f $k.Key, $k.Function)
        }
    }
    else {
        Add-Line "import attempt  $(Try-Value { Import-Module PSReadLine -PassThru -ErrorAction Stop | ForEach-Object { "worked: $($_.Version)" } })"
    }
    if ($loaded) {
        Add-Line "Selection color $(Try-Value { (Get-PSReadLineOption).SelectionColor -replace [char]27, 'ESC' })"
        Add-Line "Emphasis color  $(Try-Value { (Get-PSReadLineOption).EmphasisColor -replace [char]27, 'ESC' })"
        Add-Line "query items     $(Try-Value { (Get-PSReadLineOption).CompletionQueryItems })"
        Add-Line "extra lines     $(Try-Value { (Get-PSReadLineOption).ExtraPromptLineCount })"
    }

    Add-Section 'completion here'
    $here = Get-Location
    Add-Line "location        $($here.Path) (provider $($here.Provider.Name))"
    if ($here.Provider.Name -eq 'FileSystem') {
        $drive = Try-Value { ([IO.DriveInfo]$here.ProviderPath.Substring(0, 3)).DriveType }
        Add-Line "drive type      $drive$(if ($here.ProviderPath -like '\\*') { ' (UNC path)' })"
    }
    Add-Line "window          $(Try-Value { "$($Host.UI.RawUI.WindowSize.Width)x$($Host.UI.RawUI.WindowSize.Height), buffer $($Host.UI.RawUI.BufferSize.Width)x$($Host.UI.RawUI.BufferSize.Height)" })"
    $sample = 'Get-ChildItem .\'
    $completion = $null
    try { $completion = TabExpansion2 -inputScript $sample -cursorColumn $sample.Length } catch { Add-Line "TabExpansion2   <error: $($_.Exception.Message)>" }
    if ($completion) {
        $matches10k = @($completion.CompletionMatches)
        Add-Line "matches         $($matches10k.Count) for '$sample'"
        $missing = @($matches10k | Where-Object { $_.ResultType -eq 'ProviderItem' -or $_.ResultType -eq 'ProviderContainer' } |
            Where-Object { -not (Test-Exists ($_.CompletionText.Trim("'", '"', '&', ' '))) })
        Add-Line "missing on disk $($missing.Count)$(if ($missing) { ' e.g. ' + (($missing | Select-Object -First 3 | ForEach-Object { $_.CompletionText }) -join ', ') })"
        if (Get-Command _ps10k_menu_fits -ErrorAction Ignore) { Add-Line "menu fits       $(Try-Value { _ps10k_menu_fits $sample $sample.Length })" }
    }
    $tabExpansion = Get-Command TabExpansion2 -ErrorAction Ignore
    Add-Line "TabExpansion2   $(if ($tabExpansion.ScriptBlock.File) { "overridden in $($tabExpansion.ScriptBlock.File)" } else { 'built-in' })"
    $completers = Try-Value { @(Get-Command -CommandType Function | Where-Object { $_.Name -like 'TabExpansion*' } | ForEach-Object Name) -join ', ' }
    Add-Line "completion fns  $completers"

    Add-Section 'appearance: prompt config'
    $configPath = if ($env:PS10K_CONFIG) { $env:PS10K_CONFIG } else { Join-Path $HOME '.p10k.ps1' }
    if (Test-Exists $configPath) {
        Add-Line "file            $configPath"
        foreach ($l in Get-Content -LiteralPath $configPath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }) { Add-Line "  $l" }
    }
    else { Add-Line "file            $configPath (missing: defaults)" }

    Add-Section 'appearance: PSReadLine colors'
    if ($loaded) {
        $o = Get-PSReadLineOption
        foreach ($p in $o.PSObject.Properties | Where-Object { $_.Name -like '*Color' } | Sort-Object Name) {
            Add-Line ("{0,-24} {1}" -f $p.Name, ("$($p.Value)" -replace [char]27, 'ESC'))
        }
    }

    Add-Section 'appearance: Windows Terminal'
    Add-Line "WT_PROFILE_ID   $env:WT_PROFILE_ID"
    $wtFiles = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Exists $_ }
    $wtPackage = Try-Value { (Get-AppxPackage Microsoft.WindowsTerminal* -ErrorAction Stop | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', ' }
    Add-Line "package         $wtPackage"
    foreach ($wtFile in $wtFiles) {
        Add-Line "settings        $wtFile"
        try {
            # Drop // comments and trailing commas; good enough for these keys.
            $json = (Get-Content -LiteralPath $wtFile -Raw) -replace '(?m)^\s*//.*$', '' -replace ',(\s*[}\]])', '$1'
            $wt = $json | ConvertFrom-Json
            foreach ($key in 'theme', 'useAcrylicInTabRow', 'experimental.rendering.forceFullRepaint', 'rendering.graphicsAPI') {
                if ($wt.PSObject.Properties[$key]) { Add-Line ("  {0,-22} {1}" -f $key, $wt.$key) }
            }
            Add-Line "  defaults        $($wt.profiles.defaults | ConvertTo-Json -Compress -Depth 5)"
            $current = @($wt.profiles.list) | Where-Object { $_.guid -eq $env:WT_PROFILE_ID }
            if (-not $current) { $current = @($wt.profiles.list) | Where-Object { $_.guid -eq $wt.defaultProfile } }
            if ($current) { Add-Line "  this profile    $($current | ConvertTo-Json -Compress -Depth 5)" }
            $schemeName = if ($current -and $current.colorScheme) { $current.colorScheme } else { $wt.profiles.defaults.colorScheme }
            $scheme = @($wt.schemes) | Where-Object { $_.name -eq $schemeName }
            Add-Line "  scheme in use   $(if ($schemeName) { $schemeName } else { '(built-in default)' })$(if ($schemeName -and -not $scheme) { '  (NOT in schemes list)' })"
            if ($scheme) { Add-Line "  scheme          $($scheme | ConvertTo-Json -Compress)" }
        }
        catch { Add-Line "  <could not parse: $($_.Exception.Message)>" }
    }

    Add-Section 'recent errors'
    foreach ($e in $recentErrors) { Add-Line "  $(("$e" -split "`r?`n")[0])" }

    $out = Join-Path $HOME 'ps10k-diagnose.txt'
    $lines | Set-Content -LiteralPath $out -Encoding UTF8
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host "saved to $out" -ForegroundColor Green
}
