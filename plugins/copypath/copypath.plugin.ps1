# copypath plugin: copy paths and file contents to the clipboard.
#   copypath [path]   copy the absolute path (default: current directory)
#   copyfile <file>   copy the file's contents

function global:copypath([string]$Path = '.') {
    $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    Set-Clipboard -Value $full
    Write-Host "$full copied to clipboard."
}

function global:copyfile([Parameter(Mandatory)][string]$Path) {
    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | Set-Clipboard
    Write-Host "$Path copied to clipboard."
}
