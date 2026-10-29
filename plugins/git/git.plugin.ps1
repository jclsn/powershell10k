# git plugin: oh-my-zsh style git aliases plus tab completion.
#
# PowerShell resolves aliases before functions, so the built-in aliases gc, gl
# and gp are removed to make room. gm (Get-Member) and gcm (Get-Command) are
# kept unless you list them in $PS10K_GIT_OVERRIDE before loading:
#   $global:PS10K_GIT_OVERRIDE = @('gm', 'gcm')

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

$ps10kGitAliases = [ordered]@{
    g      = ''
    ga     = 'add'
    gaa    = 'add --all'
    gapa   = 'add --patch'
    gau    = 'add --update'
    gb     = 'branch'
    gba    = 'branch --all'
    gbd    = 'branch --delete'
    gbl    = 'blame -w'
    gbr    = 'branch --remote'
    gbs    = 'bisect'
    gc     = 'commit --verbose'
    gca    = 'commit --verbose --all'
    gcam   = 'commit --all --message'
    gcmsg  = 'commit --message'
    gcb    = 'checkout -b'
    gcf    = 'config --list'
    gcl    = 'clone --recurse-submodules'
    gclean = 'clean --interactive -d'
    gco    = 'checkout'
    gcp    = 'cherry-pick'
    gcpa   = 'cherry-pick --abort'
    gcpc   = 'cherry-pick --continue'
    gd     = 'diff'
    gdca   = 'diff --cached'
    gds    = 'diff --staged'
    gdw    = 'diff --word-diff'
    gf     = 'fetch'
    gfa    = 'fetch --all --prune'
    gfo    = 'fetch origin'
    gl     = 'pull'
    glg    = 'log --stat'
    glgp   = 'log --stat --patch'
    glo    = 'log --oneline --decorate'
    glog   = 'log --oneline --decorate --graph'
    gloga  = 'log --oneline --decorate --graph --all'
    gm     = 'merge'
    gma    = 'merge --abort'
    gmc    = 'merge --continue'
    gp     = 'push'
    gpd    = 'push --dry-run'
    gpf    = 'push --force-with-lease'
    gpr    = 'pull --rebase'
    gpra   = 'pull --rebase --autostash'
    gpt    = 'push --tags'
    gr     = 'remote'
    gra    = 'remote add'
    grv    = 'remote --verbose'
    grb    = 'rebase'
    grba   = 'rebase --abort'
    grbc   = 'rebase --continue'
    grbi   = 'rebase --interactive'
    grbs   = 'rebase --skip'
    grh    = 'reset'
    grhh   = 'reset --hard'
    grhs   = 'reset --soft'
    grm    = 'rm'
    grmc   = 'rm --cached'
    grs    = 'restore'
    grst   = 'restore --staged'
    grev   = 'revert'
    gsh    = 'show'
    gsb    = 'status --short --branch'
    gss    = 'status --short'
    gst    = 'status'
    gsta   = 'stash push'
    gstaa  = 'stash apply'
    gstc   = 'stash clear'
    gstd   = 'stash drop'
    gstl   = 'stash list'
    gstp   = 'stash pop'
    gsts   = 'stash show --patch'
    gsw    = 'switch'
    gswc   = 'switch --create'
    gts    = 'tag --sign'
    gwt    = 'worktree'
    gwta   = 'worktree add'
    gwtls  = 'worktree list'
    gwtrm  = 'worktree remove'
}

$ps10kGitKeep = @('gm', 'gcm') | Where-Object { @($global:PS10K_GIT_OVERRIDE) -notcontains $_ }

# All alias functions are defined by one generated script: one parse instead
# of a Set-Item per alias. Names taken by a built-in alias (gc, gl, gp) get a
# function of another name, and the alias is repointed to it, because
# aliases win over functions.
# The alias list is read once: looking up names that do not exist one by one
# makes PowerShell search every module for them.
$ps10kExisting = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($ps10kAlias in Get-Alias) { [void]$ps10kExisting.Add($ps10kAlias.Name) }
$ps10kTaken = New-Object System.Collections.ArrayList
$ps10kScript = foreach ($ps10kName in @($ps10kGitAliases.Keys)) {
    if ($ps10kGitKeep -contains $ps10kName) { continue }
    $ps10kFunction = $ps10kName
    if ($ps10kExisting.Contains($ps10kName)) { $ps10kFunction = "_ps10k_git_$ps10kName"; [void]$ps10kTaken.Add($ps10kName) }
    "function global:$ps10kFunction { git $($ps10kGitAliases[$ps10kName]) @args }"
}
. ([scriptblock]::Create($ps10kScript -join "`n"))
foreach ($ps10kName in $ps10kTaken) { _ps10k_set_alias $ps10kName "_ps10k_git_$ps10kName" }

# Aliases that need the current or main branch.
function global:gcm { git checkout (git_main_branch) @args }
function global:gcd { git checkout (git_develop_branch) @args }
function global:gmom { git merge "origin/$(git_main_branch)" @args }
function global:grbm { git rebase (git_main_branch) @args }
function global:ggpull { git pull origin (git_current_branch) @args }
function global:ggpush { git push origin (git_current_branch) @args }
function global:gpsup { git push --set-upstream origin (git_current_branch) @args }
function global:groh { git reset "origin/$(git_current_branch)" --hard }
# git add -A stages deletions too, so no separate git rm is needed.
function global:gwip { git add -A; git commit --no-verify --no-gpg-sign -m '--wip-- [skip ci]' }
function global:gunwip {
    if ((git log -n 1 --format=%s) -like '--wip--*') { git reset HEAD~1 }
}
function global:grt {
    $root = git rev-parse --show-toplevel 2>$null
    if ($root) { Set-Location -LiteralPath $root }
}
if ($ps10kGitKeep -contains 'gcm') {
    # Get-Command stays on gcm; the checkout-main helper is still reachable as gcmain.
    Remove-Item -LiteralPath Function:\gcm -ErrorAction SilentlyContinue
}
function global:gcmain { git checkout (git_main_branch) @args }

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

Remove-Variable -Name ps10kGitAliases, ps10kGitKeep, ps10kName, ps10kTaken, ps10kScript, ps10kFunction, ps10kExisting, ps10kAlias -ErrorAction SilentlyContinue
