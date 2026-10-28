<#
.SYNOPSIS
    Shows how keys arrive in this console, for debugging key bindings.
.DESCRIPTION
    Press Tab, Shift+Tab, the arrow keys and Escape; Enter ends the test.
    PSReadLine's completion menu only moves when Tab arrives as plain Tab
    (Key=Tab, char 9, no modifiers). The result is also saved to
    ~\ps10k-keytest.txt.
        & $env:PS10K_HOME\tools\keytest.ps1
#>

$lines = New-Object System.Collections.ArrayList
Write-Host 'Press Tab, Shift+Tab, Left, Right, Up, Down, Escape. Enter ends.' -ForegroundColor Cyan
while ($true) {
    $k = [Console]::ReadKey($true)
    $line = 'Key={0,-12} Char={1,-4} Modifiers={2}' -f $k.Key, [int]$k.KeyChar, $k.Modifiers
    [void]$lines.Add($line)
    Write-Host $line
    if ($k.Key -eq 'Enter') { break }
}
$out = Join-Path $HOME 'ps10k-keytest.txt'
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "saved to $out" -ForegroundColor Green
