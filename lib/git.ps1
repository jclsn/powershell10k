# Git repository detection and status parsing. A single
# `git status --porcelain=v2` call per prompt provides everything we show.

$global:_ps10k_git_exe = $null

# Walks up from $Path looking for .git; returns @{ Root; GitDir } or $null.
# Runs on every prompt, so it uses .NET file checks instead of Test-Path.
# A .git file (worktrees, submodules) points to the real git dir.
function global:_ps10k_find_repo([string]$Path) {
    $dir = $Path
    while ($dir) {
        $dotGit = [IO.Path]::Combine($dir, '.git')
        if ([IO.Directory]::Exists($dotGit)) { return @{ Root = $dir; GitDir = $dotGit } }
        if ([IO.File]::Exists($dotGit)) {
            $line = try { [IO.File]::ReadAllLines($dotGit)[0] } catch { '' }
            if ($line -match '^gitdir:\s*(.+)$') {
                $gitDir = $Matches[1].Trim()
                if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = [IO.Path]::GetFullPath([IO.Path]::Combine($dir, $gitDir)) }
                return @{ Root = $dir; GitDir = $gitDir }
            }
        }
        $dir = [IO.Path]::GetDirectoryName($dir)
    }
    $null
}

function global:_ps10k_parse_git_status([string[]]$Lines) {
    $status = @{
        Branch = $null; Oid = $null; Upstream = $null
        Ahead = 0; Behind = 0; Stash = 0
        Staged = 0; Unstaged = 0; Untracked = 0; Conflicted = 0
        Action = $null
    }
    foreach ($line in $Lines) {
        if (-not $line) { continue }
        if ($line.StartsWith('# branch.oid ')) { $status.Oid = $line.Substring(13) }
        elseif ($line.StartsWith('# branch.head ')) {
            $head = $line.Substring(14)
            if ($head -ne '(detached)') { $status.Branch = $head }
        }
        elseif ($line.StartsWith('# branch.upstream ')) { $status.Upstream = $line.Substring(18) }
        elseif ($line.StartsWith('# branch.ab ')) {
            if ($line -match '\+(\d+) -(\d+)') {
                $status.Ahead = [int]$Matches[1]
                $status.Behind = [int]$Matches[2]
            }
        }
        elseif ($line.StartsWith('# stash ')) { $status.Stash = [int]$line.Substring(8) }
        elseif ($line.StartsWith('1 ') -or $line.StartsWith('2 ')) {
            if ($line[2] -ne '.') { $status.Staged++ }
            if ($line[3] -ne '.') { $status.Unstaged++ }
        }
        elseif ($line.StartsWith('u ')) { $status.Conflicted++ }
        elseif ($line.StartsWith('? ')) { $status.Untracked++ }
    }
    $status
}

function global:_ps10k_git_action([string]$GitDir) {
    if (Test-Path -LiteralPath (Join-Path $GitDir 'rebase-merge')) { return 'rebase' }
    if (Test-Path -LiteralPath (Join-Path $GitDir 'rebase-apply')) { return 'rebase' }
    if (Test-Path -LiteralPath (Join-Path $GitDir 'MERGE_HEAD')) { return 'merge' }
    if (Test-Path -LiteralPath (Join-Path $GitDir 'CHERRY_PICK_HEAD')) { return 'cherry-pick' }
    if (Test-Path -LiteralPath (Join-Path $GitDir 'REVERT_HEAD')) { return 'revert' }
    if (Test-Path -LiteralPath (Join-Path $GitDir 'BISECT_LOG')) { return 'bisect' }
    $null
}

# Returns the parsed status for the repository containing $Path, or $null.
function global:_ps10k_git_status([string]$Path) {
    $repo = _ps10k_find_repo $Path
    if (-not $repo) { return $null }
    if (-not $global:_ps10k_git_exe) {
        $cmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { return $null }
        $global:_ps10k_git_exe = $cmd.Source
    }
    $git = $global:_ps10k_git_exe
    $lines = & $git -C $repo.Root --no-optional-locks -c core.quotepath=false status --porcelain=v2 --branch --show-stash 2>$null
    if ($LASTEXITCODE -ne 0) {
        # --show-stash needs git 2.35+.
        $lines = & $git -C $repo.Root --no-optional-locks -c core.quotepath=false status --porcelain=v2 --branch 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    $status = _ps10k_parse_git_status @($lines)
    $status.Action = _ps10k_git_action $repo.GitDir
    $status.Root = $repo.Root
    $status
}
