# Built-in aliases such as cd, gc, gl and gp are AllScope (and often
# ReadOnly) in Windows PowerShell: every scope holds a copy, so removing one
# in a nested scope (ps10k reload runs inside a function) leaves the global
# copy in place. Repointing them in the caller's scope and globally works
# everywhere, so powershell10k replaces aliases only through this.
function global:_ps10k_set_alias([string]$Name, [string]$Target) {
    Set-Alias -Name $Name -Value $Target -Option AllScope -Force -Scope 1
    Set-Alias -Name $Name -Value $Target -Option AllScope -Force -Scope Global
}
