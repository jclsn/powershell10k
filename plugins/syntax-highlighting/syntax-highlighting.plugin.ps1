# syntax-highlighting plugin: a zsh-syntax-highlighting like palette for
# PSReadLine. Commands are green, unknown input red, strings yellow.

if (Get-Module PSReadLine) {
    $ps10kE = [char]27
    Set-PSReadLineOption -Colors @{
        Command   = "$ps10kE[38;5;76m"
        Parameter = "$ps10kE[38;5;117m"
        Operator  = "$ps10kE[38;5;250m"
        Variable  = "$ps10kE[38;5;81m"
        String    = "$ps10kE[38;5;179m"
        Number    = "$ps10kE[38;5;141m"
        Type      = "$ps10kE[38;5;37m"
        Comment   = "$ps10kE[38;5;244m"
        Keyword   = "$ps10kE[38;5;170m"
        Member    = "$ps10kE[38;5;117m"
        Error     = "$ps10kE[38;5;196m"
        Emphasis  = "$ps10kE[38;5;214m"
        Default   = "$ps10kE[38;5;252m"
    }
    Remove-Variable -Name ps10kE -ErrorAction SilentlyContinue
}
