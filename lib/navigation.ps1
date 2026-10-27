# zsh-style cd: `cd` without arguments goes to your home folder, wherever you
# are (Windows PowerShell 5.1 does nothing, and on other drives such as HKCU:
# `cd ~` would mean that provider's home). Everything else is Set-Location.

function global:_ps10k_cd {
    if ($args.Count -eq 0) { Set-Location -LiteralPath $HOME; return }
    Set-Location @args
}

# cd is an AllScope alias in Windows PowerShell, copied into every scope, so it
# is repointed both here and globally instead of removed.
Set-Alias -Name cd -Value _ps10k_cd -Option AllScope -Force
Set-Alias -Name cd -Value _ps10k_cd -Option AllScope -Force -Scope Global
