# git plugin: oh-my-zsh's git aliases and functions, plus tab completion.
#
# The aliases follow oh-my-zsh's plugins/git/git.plugin.zsh. Differences:
#   - PowerShell names ignore case, so gbD, gcB and gbgD cannot exist next to
#     gbd, gcb and gbgd: use gbd --force, gco -B and gbgdf instead.
#   - Built-in aliases are replaced (gc, gl, gp, gcs, gpv), except gm
#     (Get-Member) and gcm (Get-Command), which stay unless you list them in
#     $PS10K_GIT_OVERRIDE before loading:
#       $global:PS10K_GIT_OVERRIDE = @('gm', 'gcm')
#     The checkout-main helper is always reachable as gcmain.

function global:git_current_branch {
    $ref = git symbolic-ref --quiet --short HEAD 2>$null
    if (-not $ref) { $ref = git rev-parse --short HEAD 2>$null }
    $ref
}

function global:git_main_branch {
    foreach ($name in 'main', 'trunk', 'mainline', 'default', 'master') {
        foreach ($ref in "refs/heads/$name", "refs/remotes/origin/$name", "refs/remotes/upstream/$name") {
            git show-ref -q --verify $ref 2>$null
            if ($LASTEXITCODE -eq 0) { return $name }
        }
    }
    'master'
}

function global:git_develop_branch {
    foreach ($name in 'dev', 'devel', 'develop', 'development') {
        git show-ref -q --verify "refs/heads/$name" 2>$null
        if ($LASTEXITCODE -eq 0) { return $name }
    }
    'develop'
}

# Whether git is at least $Version. Asked once, when an alias first needs it,
# so loading the plugin starts no git process.
function global:_ps10k_git_at_least([string]$Version) {
    if (-not $global:_ps10k_git_version) {
        $global:_ps10k_git_version = [version]'0.0'
        if ("$(git version 2>$null)" -match '(\d+)\.(\d+)(\.(\d+))?') { $global:_ps10k_git_version = [version]$Matches[0] }
    }
    $global:_ps10k_git_version -ge [version]$Version
}

# Local branches whose upstream is gone. git's output is translated, so it is
# forced to English to find "gone" (oh-my-zsh uses LANG=C).
function global:_ps10k_git_gone_branches {
    $saved = $env:LC_ALL
    try { $env:LC_ALL = 'C'; @(git branch --no-color -vv) | Where-Object { $_ -match ': gone\]' } }
    finally { $env:LC_ALL = $saved }
}

# Aliases that are just git and arguments.
$ps10kGitAliases = [ordered]@{
    g         = ''
    ga        = 'add'
    gaa       = 'add --all'
    gam       = 'am'
    gama      = 'am --abort'
    gamc      = 'am --continue'
    gams      = 'am --skip'
    gamscp    = 'am --show-current-patch'
    gap       = 'apply'
    gapa      = 'add --patch'
    gapt      = 'apply --3way'
    gau       = 'add --update'
    gav       = 'add --verbose'
    gb        = 'branch'
    gba       = 'branch --all'
    gbd       = 'branch --delete'
    gbl       = 'blame -w'
    gbm       = 'branch --move'
    gbnm      = 'branch --no-merged'
    gbr       = 'branch --remotes'
    gbs       = 'bisect'
    gbsb      = 'bisect bad'
    gbsg      = 'bisect good'
    gbsn      = 'bisect new'
    gbso      = 'bisect old'
    gbsr      = 'bisect reset'
    gbss      = 'bisect start'
    gc        = 'commit --verbose'
    'gc!'     = 'commit --verbose --amend'
    gca       = 'commit --verbose --all'
    'gca!'    = 'commit --verbose --all --amend'
    gcam      = 'commit --all --message'
    'gcan!'   = 'commit --verbose --all --no-edit --amend'
    'gcann!'  = 'commit --verbose --all --date=now --no-edit --amend'
    'gcans!'  = 'commit --verbose --all --signoff --no-edit --amend'
    gcas      = 'commit --all --signoff'
    gcasm     = 'commit --all --signoff --message'
    gcb       = 'checkout -b'
    gcf       = 'config --list'
    gcfu      = 'commit --fixup'
    gcl       = 'clone --recurse-submodules'
    gclean    = 'clean --interactive -d'
    gclf      = 'clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'
    gcmsg     = 'commit --message'
    gcn       = 'commit --verbose --no-edit'
    'gcn!'    = 'commit --verbose --no-edit --amend'
    gco       = 'checkout'
    gcor      = 'checkout --recurse-submodules'
    gcount    = 'shortlog --summary --numbered'
    gcp       = 'cherry-pick'
    gcpa      = 'cherry-pick --abort'
    gcpc      = 'cherry-pick --continue'
    gcs       = 'commit --gpg-sign'
    gcsm      = 'commit --signoff --message'
    gcss      = 'commit --gpg-sign --signoff'
    gcssm     = 'commit --gpg-sign --signoff --message'
    gd        = 'diff'
    gdca      = 'diff --cached'
    gdcw      = 'diff --cached --word-diff'
    gds       = 'diff --staged'
    gdt       = 'diff-tree --no-commit-id --name-only -r'
    gdup      = 'diff "@{upstream}"'
    gdw       = 'diff --word-diff'
    gf        = 'fetch'
    gfa       = 'fetch --all --tags --prune --jobs=10'
    gfo       = 'fetch origin'
    gg        = 'gui citool'
    gga       = 'gui citool --amend'
    ghh       = 'help'
    gignore   = 'update-index --assume-unchanged'
    gl        = 'pull'
    glg       = 'log --stat'
    glgg      = 'log --graph'
    glgga     = 'log --graph --decorate --all'
    glgm      = 'log --graph --max-count=10'
    glgp      = 'log --stat --patch'
    glo       = 'log --oneline --decorate'
    glod      = 'log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset"'
    glods     = 'log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset" --date=short'
    glog      = 'log --oneline --decorate --graph'
    gloga     = 'log --oneline --decorate --graph --all'
    glol      = 'log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
    glola     = 'log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all'
    glols     = 'log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --stat'
    gm        = 'merge'
    gma       = 'merge --abort'
    gmc       = 'merge --continue'
    gmff      = 'merge --ff-only'
    gms       = 'merge --squash'
    gmtl      = 'mergetool --no-prompt'
    gmtlvim   = 'mergetool --no-prompt --tool=vimdiff'
    gp        = 'push'
    gpd       = 'push --dry-run'
    'gpf!'    = 'push --force'
    gpod      = 'push origin --delete'
    gpr       = 'pull --rebase'
    gpra      = 'pull --rebase --autostash'
    gprav     = 'pull --rebase --autostash -v'
    gprv      = 'pull --rebase -v'
    gpu       = 'push upstream'
    gpv       = 'push --verbose'
    gr        = 'remote'
    gra       = 'remote add'
    grb       = 'rebase'
    grba      = 'rebase --abort'
    grbc      = 'rebase --continue'
    grbi      = 'rebase --interactive'
    grbo      = 'rebase --onto'
    grbs      = 'rebase --skip'
    grev      = 'revert'
    greva     = 'revert --abort'
    grevc     = 'revert --continue'
    grf       = 'reflog'
    grh       = 'reset'
    grhh      = 'reset --hard'
    grhk      = 'reset --keep'
    grhs      = 'reset --soft'
    grm       = 'rm'
    grmc      = 'rm --cached'
    grmv      = 'remote rename'
    grrm      = 'remote remove'
    grs       = 'restore'
    grset     = 'remote set-url'
    grss      = 'restore --source'
    grst      = 'restore --staged'
    gru       = 'reset --'
    grup      = 'remote update'
    grv       = 'remote --verbose'
    gsb       = 'status --short --branch'
    gsd       = 'svn dcommit'
    gsh       = 'show'
    gshs      = 'show --stat'
    gsi       = 'submodule init'
    gsnut     = 'status --untracked-files=no'
    gsps      = 'show --pretty=short --show-signature'
    gsr       = 'svn rebase'
    gss       = 'status --short'
    gst       = 'status'
    gsta      = 'stash push'
    gstaa     = 'stash apply'
    gstall    = 'stash --all'
    gstc      = 'stash clear'
    gstd      = 'stash drop'
    gstl      = 'stash list'
    gstp      = 'stash pop'
    gsts      = 'stash show --patch'
    gsu       = 'submodule update'
    gsuri     = 'submodule update --recursive --init'
    gsw       = 'switch'
    gswc      = 'switch --create'
    gta       = 'tag --annotate'
    gts       = 'tag --sign'
    gunignore = 'update-index --no-assume-unchanged'
    gwch      = 'log --patch --abbrev-commit --pretty=medium --raw'
    gwt       = 'worktree'
    gwta      = 'worktree add'
    gwtls     = 'worktree list'
    gwtmv     = 'worktree move'
    gwtrm     = 'worktree remove'
}

# Aliases with a bit of logic, as one-line function bodies.
$ps10kGitFunctions = [ordered]@{
    gcd                    = 'git checkout (git_develop_branch) @args'
    gcm                    = 'git checkout (git_main_branch) @args'
    gcmain                 = 'git checkout (git_main_branch) @args'
    gdct                   = 'git describe --tags (git rev-list --tags --max-count=1) @args'
    gfg                    = 'git ls-files | Select-String @args'
    ggpull                 = 'git pull origin (git_current_branch) @args'
    ggpur                  = 'ggu @args'
    ggpush                 = 'git push origin (git_current_branch) @args'
    ggsup                  = 'git branch "--set-upstream-to=origin/$(git_current_branch)" @args'
    gignored               = 'git ls-files -v | Where-Object { $_ -cmatch ''^[a-z]'' }'
    glolm                  = 'git log (git_main_branch) --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" @args'
    glom                   = 'git log --oneline --decorate --color "$(git_main_branch).." @args'
    glp                    = 'if ($args[0]) { git log "--pretty=$($args[0])" }'
    gluc                   = 'git pull upstream (git_current_branch) @args'
    glum                   = 'git pull upstream (git_main_branch) @args'
    gmom                   = 'git merge "origin/$(git_main_branch)" @args'
    gmum                   = 'git merge "upstream/$(git_main_branch)" @args'
    gpf                    = 'if (_ps10k_git_at_least 2.30) { git push --force-with-lease --force-if-includes @args } else { git push --force-with-lease @args }'
    gpoat                  = 'git push origin --all; if ($LASTEXITCODE -eq 0) { git push origin --tags }'
    gprom                  = 'git pull --rebase origin (git_main_branch) @args'
    gpromi                 = 'git pull --rebase=interactive origin (git_main_branch) @args'
    gprum                  = 'git pull --rebase upstream (git_main_branch) @args'
    gprumi                 = 'git pull --rebase=interactive upstream (git_main_branch) @args'
    gpristine              = 'git reset --hard; if ($LASTEXITCODE -eq 0) { git clean --force -dfx }'
    gpsup                  = 'git push --set-upstream origin (git_current_branch) @args'
    gpsupf                 = 'if (_ps10k_git_at_least 2.30) { git push --set-upstream origin (git_current_branch) --force-with-lease --force-if-includes @args } else { git push --set-upstream origin (git_current_branch) --force-with-lease @args }'
    grbd                   = 'git rebase (git_develop_branch) @args'
    grbm                   = 'git rebase (git_main_branch) @args'
    grbmi                  = 'git rebase (git_main_branch) --interactive @args'
    grbmia                 = 'git rebase (git_main_branch) --interactive --autosquash @args'
    grbom                  = 'git rebase "origin/$(git_main_branch)" @args'
    grbum                  = 'git rebase "upstream/$(git_main_branch)" @args'
    groh                   = 'git reset "origin/$(git_current_branch)" --hard'
    grt                    = '$top = git rev-parse --show-toplevel 2>$null; if ($top) { Set-Location -LiteralPath $top }'
    gstu                   = 'gsta --include-untracked @args'
    gswd                   = 'git switch (git_develop_branch) @args'
    gswm                   = 'git switch (git_main_branch) @args'
    gtl                    = 'git tag --sort=-v:refname -n --list "$($args[0])*"'
    gtv                    = 'git tag | Sort-Object { [regex]::Replace($_, ''\d+'', { param($m) $m.Value.PadLeft(20, ''0'') }) }'
    gunwip                 = 'if ((git log -n 1 --format=%s) -like ''--wip--*'') { git reset HEAD~1 }'
    gwip                   = 'git add -A; git commit --no-verify --no-gpg-sign --message ''--wip-- [skip ci]'''
    gwipe                  = 'git reset --hard; if ($LASTEXITCODE -eq 0) { git clean --force -df }'
    gbg                    = '_ps10k_git_gone_branches'
    gbgd                   = '_ps10k_git_gone_branches | ForEach-Object { git branch -d (($_.Substring(2) -split ''\s+'')[0]) }'
    gk                     = 'Start-Process gitk -ArgumentList ''--all'', ''--branches'''
    gke                    = 'Start-Process gitk -ArgumentList (@(''--all'') + @(git log --walk-reflogs --pretty=%h))'
    'git-svn-dcommit-push' = 'git svn dcommit; if ($LASTEXITCODE -eq 0) { git push github "$(git_main_branch):svntrunk" }'
    work_in_progress       = 'if ((git log -n 1 2>$null) -match ''--wip--'') { ''WIP!!'' }'
}

$ps10kGitKeep = @('gm', 'gcm') | Where-Object { @($global:PS10K_GIT_OVERRIDE) -notcontains $_ }

# All of them are defined by one generated script: one parse instead of a
# Set-Item each. Names taken by a built-in alias (gc, gl, gp, ...) get a
# function of another name and the alias is repointed to it, because aliases
# win over functions. The alias list is read once: looking up names that do
# not exist one by one makes PowerShell search every module for them.
$ps10kExisting = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($ps10kAlias in Get-Alias) { [void]$ps10kExisting.Add($ps10kAlias.Name) }
$ps10kBodies = [ordered]@{}
foreach ($ps10kName in $ps10kGitAliases.Keys) { $ps10kBodies[$ps10kName] = "git $($ps10kGitAliases[$ps10kName]) @args" }
foreach ($ps10kName in $ps10kGitFunctions.Keys) { $ps10kBodies[$ps10kName] = $ps10kGitFunctions[$ps10kName] }
$ps10kTaken = New-Object System.Collections.ArrayList
$ps10kScript = foreach ($ps10kName in @($ps10kBodies.Keys)) {
    if ($ps10kGitKeep -contains $ps10kName) { continue }
    $ps10kFunction = $ps10kName
    if ($ps10kExisting.Contains($ps10kName)) { $ps10kFunction = "_ps10k_git_$ps10kName"; [void]$ps10kTaken.Add($ps10kName) }
    "function global:$ps10kFunction { $($ps10kBodies[$ps10kName]) }"
}
. ([scriptblock]::Create($ps10kScript -join "`n"))
foreach ($ps10kName in $ps10kTaken) { _ps10k_set_alias $ps10kName "_ps10k_git_$ps10kName" }

# oh-my-zsh's longer git functions.

# Pull, push and force-push the current branch; one argument names another
# branch, more arguments are passed on (ggl, ggp).
function global:ggu { git pull --rebase origin $(if ($args.Count -eq 1) { $args[0] } else { git_current_branch }) }
function global:ggf { git push --force origin $(if ($args.Count -eq 1) { $args[0] } else { git_current_branch }) }
function global:ggfl { git push --force-with-lease origin $(if ($args.Count -eq 1) { $args[0] } else { git_current_branch }) }
function global:ggl {
    if ($args.Count -gt 1) { git pull origin "$args" } else { git pull origin $(if ($args.Count -eq 1) { $args[0] } else { git_current_branch }) }
}
function global:ggp {
    if ($args.Count -gt 1) { git push origin "$args" } else { git push origin $(if ($args.Count -eq 1) { $args[0] } else { git_current_branch }) }
}
function global:ggpnp { ggl @args; if ($LASTEXITCODE -eq 0) { ggp @args } }

# Copies the current branch name to the clipboard.
function global:gbcopy { $branch = git_current_branch; if ($branch) { Set-Clipboard -Value $branch } }

# Renames a branch locally and on origin.
function global:grename([string]$Old, [string]$New) {
    if (-not $Old -or -not $New) { Write-Host 'Usage: grename old_branch new_branch'; return }
    git branch -m $Old $New
    git push origin ":$Old"
    if ($LASTEXITCODE -eq 0) { git push --set-upstream origin $New }
}

# Undoes all --wip-- commits on top of the branch (gunwip undoes one).
function global:gunwipall {
    $commit = git log --grep='--wip--' --invert-grep --max-count=1 --format=format:%H
    if ($commit -and $commit -ne (git rev-parse HEAD)) { git reset $commit }
}

# Deletes merged branches, except the main and develop branch.
function global:gbda {
    $keep = @((git_main_branch), (git_develop_branch))
    foreach ($line in @(git branch --no-color --merged)) {
        if ($line -match '^[+*]') { continue }
        $branch = $line.Trim()
        if ($branch -and $keep -notcontains $branch) { git branch --delete $branch 2>$null }
    }
}

# Deletes branches that were squash-merged into the main branch.
function global:gbds {
    $default = git_main_branch
    foreach ($branch in @(git for-each-ref refs/heads/ '--format=%(refname:short)')) {
        $base = git merge-base $default $branch
        $squashed = git commit-tree (git rev-parse "$branch^{tree}") -p $base -m _
        if ("$(git cherry $default $squashed)" -like '-*') { git branch -D $branch }
    }
}

# Like gbgd, with -D: deletes gone branches even when they are not merged.
function global:gbgdf { _ps10k_git_gone_branches | ForEach-Object { git branch -D (($_.Substring(2) -split '\s+')[0]) } }

# Clones and changes into the new folder.
function global:gccd {
    git clone --recurse-submodules @args
    if ($LASTEXITCODE -ne 0) { return }
    $last = "$($args[-1])"
    if (Test-Path -LiteralPath $last -PathType Container) { Set-Location -LiteralPath $last; return }
    $repo = @($args | Where-Object { "$_" -match '^(ssh|git|ftps?|https?)://|@' })[-1]
    if ($repo) { Set-Location -LiteralPath (("$repo".TrimEnd('/') -split '[/:]')[-1] -replace '\.git$', '') }
}

# diff ignoring whitespace, in vim's view when it is installed.
function global:gdv {
    if (Get-Command view -ErrorAction SilentlyContinue) { git diff -w @args | view - } else { git diff -w @args }
}

# diff without lock files.
function global:gdnolock { git diff @args ':(exclude)package-lock.json' ':(exclude)*.lock' }

# Tab completion for git subcommands, branches and remotes.
$global:PS10K_GIT_SUBCOMMANDS = @(
    'add', 'am', 'bisect', 'blame', 'branch', 'checkout', 'cherry-pick', 'clean', 'clone', 'commit',
    'config', 'describe', 'diff', 'fetch', 'grep', 'init', 'log', 'merge', 'mv', 'pull', 'push',
    'rebase', 'reflog', 'remote', 'reset', 'restore', 'revert', 'rm', 'show', 'stash', 'status',
    'submodule', 'switch', 'tag', 'worktree'
)

Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $words = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    $position = $words.Count
    if ($wordToComplete) { $position-- }
    $candidates = @()
    if ($position -le 1) {
        $candidates = $global:PS10K_GIT_SUBCOMMANDS
    }
    else {
        switch ($words[1]) {
            { $_ -in 'checkout', 'switch', 'merge', 'rebase', 'branch', 'log', 'diff', 'cherry-pick', 'reset' } {
                $candidates = @(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null)
            }
            { $_ -in 'push', 'pull', 'fetch', 'remote' } {
                $candidates = @(git remote 2>$null)
                if ($position -ge 3) { $candidates = @(git for-each-ref --format='%(refname:short)' refs/heads 2>$null) }
            }
            default { return }
        }
    }
    $candidates | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object -Unique | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Remove-Variable -Name ps10kGitAliases, ps10kGitFunctions, ps10kGitKeep, ps10kName, ps10kTaken, ps10kScript, ps10kFunction, ps10kExisting, ps10kAlias, ps10kBodies -ErrorAction SilentlyContinue
