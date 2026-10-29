# zsh-style cd: `cd` without arguments goes to your home folder, wherever you
# are (Windows PowerShell 5.1 does nothing, and on other drives such as HKCU:
# `cd ~` would mean that provider's home). Everything else is Set-Location.

function global:_ps10k_cd {
    if ($args.Count -eq 0) { Set-Location -LiteralPath $HOME; return }
    Set-Location @args
}

_ps10k_set_alias cd _ps10k_cd
