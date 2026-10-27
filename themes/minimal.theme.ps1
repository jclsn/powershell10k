# minimal theme: a single line "dir branch >" prompt without special fonts.
# Shows how a theme only needs to define a global prompt function.

function global:prompt {
    $ok = $?
    $exitCode = $global:LASTEXITCODE
    $e = [char]27
    $location = $executionContext.SessionState.Path.CurrentLocation
    $path = $location.Path
    if ($location.Provider.Name -eq 'FileSystem' -and $HOME -and $path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        $path = '~' + $path.Substring($HOME.Length)
    }
    $branch = ''
    if ($location.Provider.Name -eq 'FileSystem') {
        $status = _ps10k_git_status $location.ProviderPath
        if ($status) {
            $name = if ($status.Branch) { $status.Branch } else { '@' + "$($status.Oid)".Substring(0, [Math]::Min(7, "$($status.Oid)".Length)) }
            $dirty = if ($status.Staged + $status.Unstaged + $status.Untracked + $status.Conflicted -gt 0) { '*' } else { '' }
            $branch = " $e[38;5;242m$name$dirty$e[0m"
        }
    }
    $char = if ($ok) { "$e[38;5;76m>$e[0m" } else { "$e[38;5;196m>$e[0m" }
    $global:LASTEXITCODE = $exitCode
    "$e[38;5;39m$path$e[0m$branch $char "
}
