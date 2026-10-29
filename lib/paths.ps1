# Plugin and theme lookup. Files in $PS10K_CUSTOM win over bundled ones,
# just like $ZSH_CUSTOM in oh-my-zsh.

function global:_ps10k_find_plugin([string]$Name) {
    foreach ($root in @($global:PS10K_CUSTOM, $env:PS10K_HOME)) {
        if (-not $root) { continue }
        $path = [IO.Path]::Combine($root, 'plugins', $Name, "$Name.plugin.ps1")
        if ([IO.File]::Exists($path)) { return $path }
    }
    $null
}

function global:_ps10k_find_theme([string]$Name) {
    foreach ($root in @($global:PS10K_CUSTOM, $env:PS10K_HOME)) {
        if (-not $root) { continue }
        $path = [IO.Path]::Combine($root, 'themes', "$Name.theme.ps1")
        if ([IO.File]::Exists($path)) { return $path }
    }
    $null
}

# Full path of a program on PATH (git, node, ...), or $null. Like
# Get-Command -CommandType Application, but without command discovery, which
# costs about 80 ms on first use. Cached until PATH changes.
function global:_ps10k_find_exe([string]$Name) {
    $cache = $global:_ps10k_exe_cache
    if (-not $cache -or $cache.Path -ne $env:PATH) {
        $cache = $global:_ps10k_exe_cache = @{ Path = $env:PATH; Found = @{} }
    }
    if ($cache.Found.ContainsKey($Name)) { return $cache.Found[$Name] }
    $found = $null
    foreach ($dir in $env:PATH.Split(';')) {
        if (-not $dir) { continue }
        foreach ($extension in '.exe', '.cmd', '.bat') {
            $candidate = try { [IO.Path]::Combine($dir.Trim('"'), $Name + $extension) } catch { continue }
            if ([IO.File]::Exists($candidate)) { $found = $candidate; break }
        }
        if ($found) { break }
    }
    $cache.Found[$Name] = $found
    $found
}

function global:_ps10k_list_dir_names([string]$Kind) {
    $names = @{}
    foreach ($root in @($env:PS10K_HOME, $global:PS10K_CUSTOM)) {
        if (-not $root) { continue }
        $dir = Join-Path $root $Kind
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        if ($Kind -eq 'plugins') {
            Get-ChildItem -LiteralPath $dir -Directory | Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).plugin.ps1")
            } | ForEach-Object { $names[$_.Name] = $true }
        }
        else {
            Get-ChildItem -LiteralPath $dir -Filter '*.theme.ps1' -File |
                ForEach-Object { $names[($_.Name -replace '\.theme\.ps1$', '')] = $true }
        }
    }
    @($names.Keys | Sort-Object)
}
