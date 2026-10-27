# Plugin and theme lookup. Files in $PS10K_CUSTOM win over bundled ones,
# just like $ZSH_CUSTOM in oh-my-zsh.

function global:_ps10k_find_plugin([string]$Name) {
    foreach ($root in @($global:PS10K_CUSTOM, $env:PS10K_HOME)) {
        if (-not $root) { continue }
        $path = Join-Path $root "plugins\$Name\$Name.plugin.ps1"
        if (Test-Path -LiteralPath $path) { return $path }
    }
    $null
}

function global:_ps10k_find_theme([string]$Name) {
    foreach ($root in @($global:PS10K_CUSTOM, $env:PS10K_HOME)) {
        if (-not $root) { continue }
        $path = Join-Path $root "themes\$Name.theme.ps1"
        if (Test-Path -LiteralPath $path) { return $path }
    }
    $null
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
