# powershell10k

[![tests](https://github.com/jclsn/powershell10k/actions/workflows/tests.yml/badge.svg)](https://github.com/jclsn/powershell10k/actions/workflows/tests.yml)

oh-my-zsh and powerlevel10k for PowerShell and Windows Terminal. Pure
PowerShell, Windows PowerShell 5.1 and PowerShell 7, **no administrator rights
needed**.

<img width="439" height="131" alt="image" src="https://github.com/user-attachments/assets/a13263e4-74ff-4780-90a6-59d9304573b4" />

## Features

- powerlevel10k prompt with a `p10k configure` wizard
- Syntax highlighting: commands green or red, existing paths underlined
- History search: type `git`, press <kbd>Up</kbd>
- Tab completion grid with colored folders, executables and archives
- Optional vi mode and inline suggestions
- oh-my-zsh style plugins, such as `git` aliases and `z`
- `cd` without arguments goes home, `cd ...` goes up two folders
- Works offline: the font and PSReadLine are bundled

## Install

```powershell
git clone https://github.com/jclsn/powershell10k.git
cd powershell10k
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Restart Windows Terminal; the configuration wizard starts in the first tab.

Everything is installed for your user only: the framework in `~\.powershell10k`,
the font, a block in your PowerShell profile and Windows Terminal's font
setting. Backups are saved next to every changed file. Running the installer
again updates it and keeps your plugins.

| Option | Effect |
| --- | --- |
| `-Plugins git,z,vi-mode` | choose plugins |
| `-SkipFont -SkipTerminal` | keep your own font |
| `-KeepLogo` | keep the PowerShell startup banner |
| `-RepoUrl https://github.com/jclsn/powershell10k.git` | install with git, enables `ps10k update` |

## Usage

| Command | Effect |
| --- | --- |
| `p10k configure` | run the wizard again |
| `p10k edit` | edit `~/.p10k.ps1` |
| `ps10k plugins` | list plugins |
| `ps10k reload` | reload after a change |
| `ps10k doctor` | check the setup |
| `ps10k uninstall` | remove it again |

Plugins are listed in your profile (`notepad $PROFILE`):

```powershell
$global:PS10K_PLUGINS = @('git', 'z', 'aliases', 'autosuggestions', 'syntax-highlighting', 'vi-mode')
```

## Plugins

| Plugin | What it does |
| --- | --- |
| `git` | all of oh-my-zsh's git aliases and functions (`gst`, `gco`, `gp`, `ggpush`, ...) and completion |
| `z` | jump to frequently used folders: `z proj` |
| `aliases` | `..`, `...` (also in paths: `ls ....\src`), `ll`, `take`, `touch`, `which`, `pwsh` (when PowerShell 7 is missing) and more |
| `autosuggestions` | history search and the Tab completion grid |
| `syntax-highlighting` | colors as you type |
| `vi-mode` | vi key bindings, like `bindkey -v` |
| `extract` | `x file.zip` unpacks any archive |
| `web-search` | `google`, `github`, `wiki`, ... from the shell |
| `copypath` | copy a path to the clipboard |

Each plugin's keys and options are explained in comments in its file under
`plugins\`.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Add `-Area git, plugins` to run only some areas. GitHub Actions runs the
tests on every push and pull request.

## Troubleshooting

Run `ps10k doctor`. For a full report, run this in the tab where something is
wrong and attach `~\ps10k-diagnose.txt` to your issue:

```powershell
. $env:PS10K_HOME\tools\diagnose.ps1
```

## Credits

Inspired by [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) and
[powerlevel10k](https://github.com/romkatv/powerlevel10k). The bundled font is
[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) with
[Nerd Fonts](https://www.nerdfonts.com) glyphs; see
[fonts/README.md](fonts/README.md) for its licenses.
