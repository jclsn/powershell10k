# Static checks over every script.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'all scripts parse and are ASCII-only' {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\(\.git|modules)\\' -and $_.Extension -eq '.ps1' }) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "$($file.Name): $($errors[0].Message)" }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw "$($file.Name) contains non-ASCII bytes" }
    }
}
