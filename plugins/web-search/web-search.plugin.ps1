# web-search plugin: search the web from the prompt, e.g. `google powershell splatting`.

$global:PS10K_SEARCH_ENGINES = @{
    google        = 'https://www.google.com/search?q='
    bing          = 'https://www.bing.com/search?q='
    ddg           = 'https://duckduckgo.com/?q='
    github        = 'https://github.com/search?q='
    stackoverflow = 'https://stackoverflow.com/search?q='
    wiki          = 'https://en.wikipedia.org/w/index.php?search='
    youtube       = 'https://www.youtube.com/results?search_query='
}

function global:web_search {
    param([Parameter(Mandatory)][string]$Engine, [Parameter(ValueFromRemainingArguments)][string[]]$Query)
    $base = $global:PS10K_SEARCH_ENGINES[$Engine]
    if (-not $base) { Write-Error "web_search: unknown engine '$Engine'"; return }
    if (-not $Query) { Start-Process ([uri]$base).GetLeftPart('Authority'); return }
    Start-Process ($base + [uri]::EscapeDataString($Query -join ' '))
}

foreach ($ps10kEngine in @($global:PS10K_SEARCH_ENGINES.Keys)) {
    Set-Item -Path "Function:global:$ps10kEngine" -Value ([scriptblock]::Create("web_search $ps10kEngine @args"))
}
Remove-Variable -Name ps10kEngine -ErrorAction SilentlyContinue
