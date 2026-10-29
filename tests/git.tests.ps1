# lib/git.ps1 and the git segment.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

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

# A throwaway repository with one commit on $Branch.
function New-TestRepo([string]$Name, [string]$Branch = 'main') {
    $path = Join-Path $work $Name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    git -C $path init -q -b $Branch 2>$null
    git -C $path -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>$null
    $path
}

Test-Case 'repositories are found from subfolders and worktree links' {
    $repo = New-TestRepo 'find-repo'
    New-Item -ItemType Directory -Path (Join-Path $repo 'a\b') -Force | Out-Null
    $found = _ps10k_find_repo (Join-Path $repo 'a\b')
    Assert-Equal $repo $found.Root
    Assert-Equal (Join-Path $repo '.git') $found.GitDir
    $linked = Join-Path $work 'linked-worktree'
    New-Item -ItemType Directory -Path $linked -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $linked '.git') -Value 'gitdir: ../find-repo/.git'
    Assert-Equal (Join-Path $repo '.git') (_ps10k_find_repo $linked).GitDir 'a .git file points to the real git dir'
    Assert-True ($null -eq (_ps10k_find_repo $env:SystemRoot)) 'no repository'
}

Test-Case 'in-progress git actions are detected' {
    $gitDir = Join-Path $work 'fake-gitdir'
    New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
    Assert-True ($null -eq (_ps10k_git_action $gitDir)) 'nothing in progress'
    foreach ($case in @(@('BISECT_LOG', 'bisect'), @('REVERT_HEAD', 'revert'), @('CHERRY_PICK_HEAD', 'cherry-pick'), @('MERGE_HEAD', 'merge'), @('rebase-apply', 'rebase'))) {
        New-Item -ItemType File -Path (Join-Path $gitDir $case[0]) -Force | Out-Null
        Assert-Equal $case[1] (_ps10k_git_action $gitDir) $case[0]
    }
}

Test-Case 'git status reads real repositories' {
    $repo = New-TestRepo 'status-repo'
    $clean = _ps10k_git_status $repo
    Assert-Equal 'main' $clean.Branch
    Assert-Equal 0 ($clean.Staged + $clean.Unstaged + $clean.Untracked + $clean.Conflicted + $clean.Stash)
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'x'
    git -C $repo add file.txt 2>$null
    git -C $repo -c user.name=t -c user.email=t@t stash -q 2>$null
    $stashed = _ps10k_git_status $repo
    Assert-Equal 1 $stashed.Stash 'stash count'
    git -C $repo checkout -q --detach 2>$null
    $detached = _ps10k_git_status $repo
    Assert-True (-not $detached.Branch) 'detached HEAD has no branch'
    Assert-True ($detached.Oid.Length -ge 7)
    Assert-True ($null -eq (_ps10k_git_status $env:SystemRoot)) 'outside a repository'
}

Test-Case 'git segment: detached HEAD, long branches, actions and outside repos' {
    $repo = New-TestRepo 'segment-repo' 'feature/a-really-long-branch-name-that-goes-on-and-on'
    $saved = $global:P10K
    try {
        $global:P10K = _ps10k_default_config
        Push-Location -LiteralPath $repo
        try {
            $ctx = @{ Location = $executionContext.SessionState.Path.CurrentLocation }
            $long = & $global:PS10K_SEGMENTS['git'] $ctx
            Assert-True ($long.Text.Length -le 32) 'long branch names are shortened'
            Assert-True ($long.Text.Contains([string][char]0x2026)) 'with an ellipsis'
            Assert-Equal 'clean' $long.State
            New-Item -ItemType File -Path (Join-Path $repo '.git\MERGE_HEAD') | Out-Null
            $merging = & $global:PS10K_SEGMENTS['git'] $ctx
            Assert-True ($merging.Text -match 'merge') 'action shown'
            Assert-Equal 'conflicted' $merging.State
            Remove-Item -LiteralPath (Join-Path $repo '.git\MERGE_HEAD')
            git -C $repo checkout -q --detach 2>$null
            Assert-True ((& $global:PS10K_SEGMENTS['git'] $ctx).Text -match '^@[0-9a-f]{7}') 'detached HEAD shows the commit'
        }
        finally { Pop-Location }
        Push-Location -LiteralPath $env:SystemRoot
        try { Assert-True ($null -eq (& $global:PS10K_SEGMENTS['git'] @{ Location = $executionContext.SessionState.Path.CurrentLocation })) }
        finally { Pop-Location }
    }
    finally { $global:P10K = $saved }
}

Test-Case 'git plugin: branch helpers, aliases and wip commits' {
    $repo = New-TestRepo 'plugin-repo' 'trunk'
    Push-Location -LiteralPath $repo
    try {
        Assert-Equal 'trunk' (git_current_branch)
        Assert-Equal 'trunk' (git_main_branch) 'trunk counts as the main branch'
        Assert-Equal 'develop' (git_develop_branch) 'fallback without a develop branch'
        git branch dev 2>$null
        Assert-Equal 'dev' (git_develop_branch)
        Assert-Equal 'git add --all @args' (Get-Command gaa).ScriptBlock.ToString()
        Assert-Equal 'git status @args' (Get-Command gst).ScriptBlock.ToString()
        Assert-Equal '_ps10k_git_gc' (Get-Alias gc).Definition 'the built-in gc alias is repointed'
        Assert-Equal 'git commit --verbose @args' (Get-Command _ps10k_git_gc).ScriptBlock.ToString()
        Assert-Equal '_ps10k_git_gc' (& { (Get-Alias gc).Definition }) 'also in nested scopes'
        Assert-Equal 'Alias' (Get-Command gm).CommandType 'gm stays Get-Member'
        Assert-True (Get-Command gcmain -CommandType Function)
        Set-Content -LiteralPath (Join-Path $repo 'work.txt') -Value 'x'
        $env:GIT_AUTHOR_NAME = 't'; $env:GIT_AUTHOR_EMAIL = 't@t'; $env:GIT_COMMITTER_NAME = 't'; $env:GIT_COMMITTER_EMAIL = 't@t'
        gwip *> $null
        Assert-True ((git log -n 1 --format=%s) -like '--wip--*') 'gwip commits everything'
        gunwip *> $null
        Assert-Equal 'init' (git log -n 1 --format=%s) 'gunwip undoes it'
        New-Item -ItemType Directory -Path (Join-Path $repo 'deep\er') -Force | Out-Null
        Set-Location -LiteralPath (Join-Path $repo 'deep\er')
        grt
        Assert-Equal $repo (Get-Location).Path 'grt goes to the repository root'
    }
    finally {
        Pop-Location
        foreach ($n in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL') { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
    }
    # Outside a repository git writes errors, which the plugin silences with
    # 2>$null; under the tests' Stop preference those would throw instead.
    Push-Location -LiteralPath $env:SystemRoot
    try { $ErrorActionPreference = 'Continue'; Assert-Equal 'master' (git_main_branch) 'master outside a repository' }
    finally { Pop-Location }
}

Test-Case 'git completion offers subcommands, branches and remotes' {
    $repo = New-TestRepo 'complete-repo'
    git -C $repo branch feature-x 2>$null
    git -C $repo remote add upstream https://example.invalid/x.git 2>$null
    Push-Location -LiteralPath $repo
    try {
        function Get-Completions([string]$Line) { @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches | ForEach-Object { _ps10k_strip_ansi $_.CompletionText }) }
        Assert-True ((Get-Completions 'git chec') -contains 'checkout')
        Assert-True ((Get-Completions 'git checkout feat') -contains 'feature-x')
        Assert-True ((Get-Completions 'git push up') -contains 'upstream')
    }
    finally { Pop-Location }
}
