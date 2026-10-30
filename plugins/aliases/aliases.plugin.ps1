# aliases plugin: common directory and file helpers.

function global:.. { Set-Location .. }
function global:... { Set-Location ..\.. }
function global:.... { Set-Location ..\..\.. }
function global:..... { Set-Location ..\..\..\.. }

function global:l { Get-ChildItem -Force @args }
function global:la { Get-ChildItem -Force @args }
function global:ll { Get-ChildItem @args | Format-Table Mode, LastWriteTime, Length, Name -AutoSize }
function global:lsd { Get-ChildItem -Directory @args }

# take/mkcd: create a directory and change into it.
function global:take([Parameter(Mandatory)][string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location -LiteralPath $Path
}
Set-Alias -Name mkcd -Value take -Scope Global

# touch a b and touch a, b: a comma list arrives as one array argument.
function global:touch {
    foreach ($path in @($args | ForEach-Object { $_ })) {
        if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTime = Get-Date }
        else { New-Item -ItemType File -Path $path | Out-Null }
    }
}

function global:which([Parameter(Mandatory)][string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { Write-Error "${Name} not found"; return }
    switch ($cmd.CommandType) {
        'Application' { $cmd.Source }
        'Alias' { "$Name -> $($cmd.Definition)" }
        default { "$($cmd.CommandType) $($cmd.Name)" }
    }
}

# grep for machines without grep.exe: files, or piped input matched as it is
# displayed (ls | grep foo). Always defined as _ps10k_grep, grep only when
# missing.
function global:_ps10k_grep {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Pattern,
        [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Path,
        [Parameter(ValueFromPipeline)]$InputObject
    )
    begin { $piped = New-Object System.Collections.ArrayList }
    process { if ($null -ne $InputObject) { [void]$piped.Add($InputObject) } }
    end {
        if ($Path) { Select-String -Pattern $Pattern -Path $Path }
        else { $piped | Out-String -Stream | Select-String -Pattern $Pattern }
    }
}
if (-not (Get-Command grep -CommandType Application -ErrorAction SilentlyContinue)) {
    Set-Alias -Name grep -Value _ps10k_grep -Scope Global
}

function global:h { Get-History @args }
function global:hs([string]$Pattern) {
    $file = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath
    if ($file -and (Test-Path -LiteralPath $file)) { Select-String -LiteralPath $file -Pattern $Pattern -SimpleMatch | ForEach-Object Line }
}
function global:path { $env:PATH -split ';' | Where-Object { $_ } }
