# Prompt segments. Each segment is a scriptblock that receives the prompt
# context and returns $null (hidden) or a hashtable:
#   @{ Icon = '<icon name>'; Text = '...'; State = 'optional state' }
# Custom segments may also return IconText (a literal glyph) and Fg/Bg colors.
# Register your own with: $PS10K_SEGMENTS['name'] = { param($ctx) @{ Text = 'hi' } }

$global:PS10K_SEGMENTS = @{}
$global:_ps10k_cache = @{}

try {
    $global:_ps10k_is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $global:_ps10k_is_admin = $false }

# Searches $Path and its parents for any of $Names; returns the first hit.
function global:_ps10k_find_up([string]$Path, [string[]]$Names) {
    $dir = $Path
    while ($dir) {
        foreach ($name in $Names) {
            $candidate = Join-Path $dir $name
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        $parent = Split-Path -Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    $null
}

function global:_ps10k_format_duration([TimeSpan]$Duration, [int]$Precision) {
    $total = $Duration.TotalSeconds
    if ($total -lt 60) {
        if ($Precision -gt 0) { return ('{0:F' + $Precision + '}s') -f $total }
        return '{0}s' -f [int][Math]::Floor($total)
    }
    $parts = @()
    if ($Duration.Days -gt 0) { $parts += '{0}d' -f $Duration.Days }
    if ($Duration.Hours -gt 0 -or $parts) { $parts += '{0}h' -f $Duration.Hours }
    $parts += '{0}m' -f $Duration.Minutes
    $parts += '{0}s' -f $Duration.Seconds
    $parts -join ' '
}

function global:_ps10k_shorten_path([string]$Path, [int]$MaxLength, [string]$Separator) {
    $parts = $Path -split '[\\/]'
    $display = $parts -join $Separator
    if ($MaxLength -le 0 -or $display.Length -le $MaxLength -or $parts.Count -le 2) { return ,$parts }
    for ($i = 1; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]
        if ($part.Length -le 1) { continue }
        $parts[$i] = if ($part.StartsWith('.')) { $part.Substring(0, 2) } else { $part.Substring(0, 1) }
        if (($parts -join $Separator).Length -le $MaxLength) { break }
    }
    ,$parts
}

$global:PS10K_SEGMENTS['os_icon'] = {
    param($ctx)
    @{ Icon = 'os'; Text = '' }
}

$global:PS10K_SEGMENTS['dir'] = {
    param($ctx)
    $cfg = $global:P10K
    $location = $ctx.Location
    $isFs = $location.Provider.Name -eq 'FileSystem'
    $path = if ($isFs) { $location.ProviderPath } else { $location.Path }
    $icon = 'folder'
    if ($isFs -and $HOME) {
        $homeDir = $HOME.TrimEnd('\')
        if ($path -eq $homeDir) { $path = '~'; $icon = 'home' }
        elseif ($path.StartsWith($homeDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $path = '~' + $path.Substring($homeDir.Length)
            $icon = 'home'
        }
    }
    $sep = $cfg.DirSeparator
    $parts = _ps10k_shorten_path -Path $path.TrimEnd('\') -MaxLength $cfg.DirMaxLength -Separator $sep
    if ($parts.Count -eq 1 -and $parts[0] -match '^[A-Za-z]:$') { $parts[0] += $sep }
    if ($parts.Count -gt 1 -and $cfg.Style -ne 'pure') {
        $last = $parts.Count - 1
        $parts[$last] = $global:PS10K_BOLD + $parts[$last] + $global:PS10K_NOBOLD
    }
    @{ Icon = $icon; Text = ($parts -join $sep) }
}

$global:PS10K_SEGMENTS['git'] = {
    param($ctx)
    if ($ctx.Location.Provider.Name -ne 'FileSystem') { return $null }
    $s = _ps10k_git_status $ctx.Location.ProviderPath
    if (-not $s) { return $null }
    $cfg = $global:P10K
    if ($s.Branch) {
        $name = $s.Branch
        $max = [int]$cfg.GitMaxBranchLength
        if ($max -gt 0 -and $name.Length -gt $max) {
            $half = [int][Math]::Floor(($max - 1) / 2)
            $name = $name.Substring(0, $half) + (_ps10k_icon 'ellipsis') + $name.Substring($name.Length - $half)
        }
    }
    elseif ($s.Oid -and $s.Oid -ne '(initial)') { $name = '@' + $s.Oid.Substring(0, [Math]::Min(7, $s.Oid.Length)) }
    else { $name = '@initial' }

    $text = $name
    $sync = ''
    if ($s.Behind -gt 0) { $sync += (_ps10k_icon 'behind') + $s.Behind }
    if ($s.Ahead -gt 0) { $sync += (_ps10k_icon 'ahead') + $s.Ahead }
    if ($sync) { $text += ' ' + $sync }
    if ($s.Stash -gt 0) { $text += " *$($s.Stash)" }
    if ($s.Action) { $text += " $($s.Action)" }
    if ($s.Conflicted -gt 0) { $text += " ~$($s.Conflicted)" }
    if ($s.Staged -gt 0) { $text += " +$($s.Staged)" }
    if ($s.Unstaged -gt 0) { $text += " !$($s.Unstaged)" }
    if ($s.Untracked -gt 0) { $text += " ?$($s.Untracked)" }

    $state = 'clean'
    if ($s.Conflicted -gt 0 -or $s.Action) { $state = 'conflicted' }
    elseif ($s.Staged -gt 0 -or $s.Unstaged -gt 0) { $state = 'modified' }
    elseif ($s.Untracked -gt 0) { $state = 'untracked' }
    @{ Icon = 'branch'; Text = $text; State = $state }
}

$global:PS10K_SEGMENTS['status'] = {
    param($ctx)
    if ($ctx.Success) {
        if ($global:P10K.StatusShowOk) { return @{ Icon = 'ok'; Text = ''; State = 'ok' } }
        return $null
    }
    $text = if ($ctx.ExitCode -and $ctx.ExitCode -ne 0) { "$($ctx.ExitCode)" } else { '' }
    $icon = 'fail'
    if ($global:P10K.Mode -eq 'ascii' -and $text) { $icon = $null }
    @{ Icon = $icon; Text = $text; State = 'error' }
}

$global:PS10K_SEGMENTS['command_execution_time'] = {
    param($ctx)
    if (-not $ctx.Duration) { return $null }
    if ($ctx.Duration.TotalSeconds -lt $global:P10K.ExecTimeThreshold) { return $null }
    @{ Icon = 'exec'; Text = (_ps10k_format_duration $ctx.Duration ([int]$global:P10K.ExecTimePrecision)) }
}

$global:PS10K_SEGMENTS['background_jobs'] = {
    param($ctx)
    $running = @(Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' }).Count
    if ($running -eq 0) { return $null }
    $text = if ($running -gt 1) { "$running" } else { '' }
    @{ Icon = 'jobs'; Text = $text }
}

$global:PS10K_SEGMENTS['virtualenv'] = {
    param($ctx)
    if (-not $env:VIRTUAL_ENV) { return $null }
    @{ Icon = 'python'; Text = (Split-Path -Leaf $env:VIRTUAL_ENV) }
}

$global:PS10K_SEGMENTS['anaconda'] = {
    param($ctx)
    if (-not $env:CONDA_DEFAULT_ENV) { return $null }
    @{ Icon = 'python'; Text = $env:CONDA_DEFAULT_ENV }
}

$global:PS10K_SEGMENTS['node_version'] = {
    param($ctx)
    if ($ctx.Location.Provider.Name -ne 'FileSystem') { return $null }
    if ($global:P10K.NodeProjectOnly -and -not (_ps10k_find_up $ctx.Location.ProviderPath @('package.json'))) { return $null }
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { return $null }
    $key = "node:$($node.Source)"
    if (-not $global:_ps10k_cache.ContainsKey($key)) {
        $global:_ps10k_cache[$key] = ("$(& $node.Source --version 2>$null)").Trim().TrimStart('v')
    }
    if (-not $global:_ps10k_cache[$key]) { return $null }
    @{ Icon = 'node'; Text = $global:_ps10k_cache[$key] }
}

$global:PS10K_SEGMENTS['dotnet_version'] = {
    param($ctx)
    if ($ctx.Location.Provider.Name -ne 'FileSystem') { return $null }
    $dir = $ctx.Location.ProviderPath
    $isProject = (Test-Path -LiteralPath (Join-Path $dir 'global.json')) -or
        @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.csproj', '.fsproj', '.vbproj', '.sln' }).Count -gt 0
    if (-not $isProject) { return $null }
    $key = "dotnet:$dir"
    if (-not $global:_ps10k_cache.ContainsKey($key)) {
        $dotnet = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $global:_ps10k_cache[$key] = if ($dotnet) { ("$(& $dotnet.Source --version 2>$null)").Trim() } else { '' }
    }
    if (-not $global:_ps10k_cache[$key]) { return $null }
    @{ Icon = 'dotnet'; Text = $global:_ps10k_cache[$key] }
}

$global:PS10K_SEGMENTS['aws'] = {
    param($ctx)
    $awsProfile = if ($env:AWS_VAULT) { $env:AWS_VAULT } elseif ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { $env:AWS_DEFAULT_PROFILE }
    if (-not $awsProfile) { return $null }
    @{ Icon = 'aws'; Text = $awsProfile }
}

$global:PS10K_SEGMENTS['context'] = {
    param($ctx)
    $remote = [bool]($env:SSH_CONNECTION -or $env:SSH_CLIENT)
    if (-not ($global:_ps10k_is_admin -or $remote -or $global:P10K.ContextAlwaysShow)) { return $null }
    $state = if ($global:_ps10k_is_admin) { 'admin' } elseif ($remote) { 'remote' } else { 'default' }
    $icon = if ($global:_ps10k_is_admin) { 'admin' } else { $null }
    @{ Icon = $icon; Text = "$env:USERNAME@$env:COMPUTERNAME"; State = $state }
}

$global:PS10K_SEGMENTS['time'] = {
    param($ctx)
    @{ Icon = 'time'; Text = (Get-Date -Format $global:P10K.TimeFormat) }
}
