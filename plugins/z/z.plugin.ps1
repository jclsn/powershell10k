# z plugin: jump to frecent directories.
#   z foo        jump to the best match for "foo"
#   z foo bar    all terms must match, in order
#   z -l [foo]   list matches with their scores
#   z -x         remove the current directory from the list
#   z -c foo     restrict matches to subdirectories of the current directory
# Data lives in $env:PS10K_Z_DATA (default ~/.ps10k_z), one "path|rank|time" per line.

if (-not $env:PS10K_Z_DATA) { $env:PS10K_Z_DATA = [IO.Path]::Combine($HOME, '.ps10k_z') }
$global:PS10K_Z_MAX_SCORE = 9000

function global:_ps10k_z_now { [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) }

function global:_ps10k_z_load {
    $entries = @{}
    if ([IO.File]::Exists($env:PS10K_Z_DATA)) {
        foreach ($line in [IO.File]::ReadAllLines($env:PS10K_Z_DATA)) {
            $parts = $line.Split('|')
            if ($parts.Count -ne 3) { continue }
            $entries[$parts[0]] = @{ Path = $parts[0]; Rank = [double]$parts[1]; Time = [int64]$parts[2] }
        }
    }
    $entries
}

function global:_ps10k_z_save($Entries) {
    $lines = foreach ($e in $Entries.Values) {
        '{0}|{1}|{2}' -f $e.Path, $e.Rank.ToString([Globalization.CultureInfo]::InvariantCulture), $e.Time
    }
    # Written next to the data and swapped in, so a crash cannot leave half a
    # file. .NET calls: this runs on every directory change.
    $tmp = "$($env:PS10K_Z_DATA).$PID.tmp"
    [IO.File]::WriteAllLines($tmp, [string[]]@($lines))
    if ([IO.File]::Exists($env:PS10K_Z_DATA)) { [IO.File]::Replace($tmp, $env:PS10K_Z_DATA, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $env:PS10K_Z_DATA) }
}

function global:_ps10k_z_add([string]$Path) {
    if (-not $Path -or $Path -eq $HOME) { return }
    $entries = _ps10k_z_load
    $now = _ps10k_z_now
    if ($entries.ContainsKey($Path)) {
        $entries[$Path].Rank += 1
        $entries[$Path].Time = $now
    }
    else {
        $entries[$Path] = @{ Path = $Path; Rank = 1.0; Time = $now }
    }
    $total = 0.0
    foreach ($e in $entries.Values) { $total += $e.Rank }
    if ($total -gt $global:PS10K_Z_MAX_SCORE) {
        foreach ($key in @($entries.Keys)) {
            $entries[$key].Rank *= 0.99
            if ($entries[$key].Rank -lt 1) { $entries.Remove($key) }
        }
    }
    _ps10k_z_save $entries
}

function global:_ps10k_z_frecency($Entry, [int64]$Now) {
    $age = $Now - $Entry.Time
    if ($age -lt 3600) { return $Entry.Rank * 4 }
    if ($age -lt 86400) { return $Entry.Rank * 2 }
    if ($age -lt 604800) { return $Entry.Rank / 2 }
    $Entry.Rank / 4
}

function global:_ps10k_z_matches([string[]]$Terms, [string]$Under) {
    $entries = _ps10k_z_load
    $now = _ps10k_z_now
    $pattern = (@($Terms) | ForEach-Object { [regex]::Escape($_) }) -join '.*'
    $results = foreach ($e in $entries.Values) {
        if ($Under -and -not $e.Path.StartsWith($Under, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($pattern -and $e.Path -notmatch $pattern) { continue }
        [pscustomobject]@{ Score = [Math]::Round((_ps10k_z_frecency $e $now), 2); Path = $e.Path }
    }
    @($results | Sort-Object Score -Descending)
}

function global:z {
    param(
        [Alias('List')][switch]$l,
        [Alias('Remove')][switch]$x,
        [Alias('Current')][switch]$c,
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Terms
    )
    if ($x) {
        $entries = _ps10k_z_load
        $entries.Remove((Get-Location).ProviderPath)
        _ps10k_z_save $entries
        return
    }
    $under = if ($c) { (Get-Location).ProviderPath } else { $null }
    $terms = @($Terms | Where-Object { $_ })
    $found = _ps10k_z_matches -Terms $terms -Under $under
    if ($l -or $terms.Count -eq 0) {
        $found | Sort-Object Score | Format-Table -AutoSize -HideTableHeaders
        return
    }
    $best = $found | Where-Object { Test-Path -LiteralPath $_.Path -PathType Container } | Select-Object -First 1
    if ($best) { Set-Location -LiteralPath $best.Path }
    elseif ($terms.Count -eq 1 -and (Test-Path -LiteralPath $terms[0] -PathType Container)) { Set-Location -LiteralPath $terms[0] }
    else { Write-Warning "z: no match for '$($terms -join ' ')'" }
}

Register-ArgumentCompleter -CommandName z -ParameterName Terms -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    _ps10k_z_matches -Terms @($wordToComplete) | Select-Object -First 20 | ForEach-Object {
        $quoted = if ($_.Path -match '\s') { "'$($_.Path)'" } else { $_.Path }
        [System.Management.Automation.CompletionResult]::new($quoted, $_.Path, 'ParameterValue', $_.Path)
    }
}

Add-PS10kHook -Type chpwd -Action {
    param($ctx)
    if ($ctx.Location.Provider.Name -eq 'FileSystem') { _ps10k_z_add $ctx.Location.ProviderPath }
}
