# autosuggestions plugin: zsh-autosuggestions and history-substring-search
# behaviour on top of PSReadLine.
#   Up/Down      search history for lines starting with what you typed
#   Tab          menu completion
#   Right/End    accept the inline suggestion (PSReadLine 2.1+)
#   Ctrl+Right   accept the next word of the suggestion (PSReadLine 2.1+)
# Inline suggestions need PSReadLine 2.1+. Windows PowerShell 5.1 ships 2.0;
# `ps10k doctor` explains how to upgrade it for the current user only.

if (Get-Module PSReadLine) {
    $ps10kPsrl = (Get-Module PSReadLine).Version

    Set-PSReadLineOption -HistorySearchCursorMovesToEnd -HistoryNoDuplicates -BellStyle None
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious

    if ($ps10kPsrl -ge [version]'2.1.0') {
        # Throws when output is redirected (no virtual terminal), e.g. in scripts.
        try { Set-PSReadLineOption -PredictionSource History } catch { }
        Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]27)[38;5;244m" }
        Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
        Set-PSReadLineKeyHandler -Key End -Function EndOfLine
        Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    }
    if ($ps10kPsrl -ge [version]'2.2.0' -and $global:PS10K_AUTOSUGGEST_LIST) {
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    Remove-Variable -Name ps10kPsrl -ErrorAction SilentlyContinue
}
