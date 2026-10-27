# extract plugin: `extract <archive> [...]` unpacks into a folder named after
# the archive. Uses Expand-Archive for zip and tar.exe (built into Windows 10
# 1803+) for tarballs; 7z is used for anything else when it is on PATH.

function global:extract {
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Path)
    foreach ($archive in $Path) {
        $item = Get-Item -LiteralPath $archive -ErrorAction SilentlyContinue
        if (-not $item) { Write-Error "extract: '$archive' not found"; continue }
        $name = $item.Name
        $base = $name -replace '\.(tar\.(gz|bz2|xz|zst)|tgz|tbz2?|txz|zip|7z|rar|tar|jar|war|nupkg)$', ''
        $dest = Join-Path $item.DirectoryName $base
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        switch -Regex ($name) {
            '\.(zip|jar|war|nupkg)$' { Expand-Archive -LiteralPath $item.FullName -DestinationPath $dest -Force; break }
            '\.(tar(\.(gz|bz2|xz|zst))?|tgz|tbz2?|txz)$' {
                tar -xf $item.FullName -C $dest
                break
            }
            default {
                $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
                if ($sevenZip) { & $sevenZip.Source x $item.FullName "-o$dest" -y | Out-Null }
                else { Write-Error "extract: don't know how to extract '$name' (install 7-Zip for more formats)" }
            }
        }
        Write-Host "extracted $name -> $dest"
    }
}
Set-Alias -Name x -Value extract -Scope Global
