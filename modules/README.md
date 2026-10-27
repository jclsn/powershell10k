# Bundled modules

[PSReadLine](https://github.com/PowerShell/PSReadLine) 2.4.5, copied unchanged
from the PowerShell Gallery package. Windows PowerShell 5.1 ships 2.0, which
has no inline suggestions and no vi mode cursor or prompt switch.
`install.ps1` copies it to `Documents\WindowsPowerShell\Modules` for the
current user (no administrator rights and no download needed) unless a newer
version is already installed.

PSReadLine is copyright (c) 2013 Jason Shirk and licensed under the BSD
2-Clause license, see [PSReadLine/2.4.5/License.txt](PSReadLine/2.4.5/License.txt).
