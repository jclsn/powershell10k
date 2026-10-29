# Loader and lib/: width, colors, cd.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'loader loads every plugin without warnings' {
    $warnings = . (Join-Path $root 'powershell10k.ps1') 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
    if ($warnings) { throw "warnings: $($warnings -join '; ')" }
    Assert-True (Get-Command prompt -CommandType Function)
    Assert-True (Get-Command gst -CommandType Function)
    Assert-True (Get-Command z -CommandType Function)
}

Test-Case 'display width ignores escape sequences' {
    Assert-Equal 3 (_ps10k_width "$([char]27)[38;5;1mabc$([char]27)[0m")
    Assert-Equal 2 (_ps10k_width ([string][char]0x4E2D))
    Assert-Equal 9 (_ps10k_width ("$([char]0xDC)bersicht")) 'umlauts are one column'
    Assert-Equal 3 (_ps10k_width ("a" + [char]::ConvertFromUtf32(0x1F600) + "$([char]1)")) 'emoji two columns, control characters none'
    Assert-Equal 5 (_ps10k_width 'plain') 'ASCII fast path'
    Assert-Equal 1 (_ps10k_width "$([char]27)]9;9;`"C:\`"$([char]27)\x")
}

Test-Case 'colors accept indexes, names and hex' {
    Assert-Equal "$([char]27)[38;5;4m" (_ps10k_fg 4)
    Assert-Equal "$([char]27)[48;5;1m" (_ps10k_bg 'red')
    Assert-Equal "$([char]27)[38;2;255;0;16m" (_ps10k_fg '#ff0010')
    Assert-Equal '' (_ps10k_fg $null)
}

Test-Case 'cd without arguments goes home' {
    Push-Location
    try {
        Set-Location -LiteralPath $env:SystemRoot
        cd
        Assert-Equal $HOME (Get-Location).Path
        cd -Path $env:SystemRoot
        Assert-Equal $env:SystemRoot (Get-Location).Path
        Set-Location HKCU:\Software
        cd
        Assert-Equal $HOME (Get-Location).Path 'from another provider'
    }
    finally { Pop-Location }
}
