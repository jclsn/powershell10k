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
