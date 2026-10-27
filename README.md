# powershell10k

An oh-my-zsh style framework with a powerlevel10k style prompt for PowerShell
and Windows Terminal. Pure PowerShell, works on Windows PowerShell 5.1 and
PowerShell 7, and **installs without administrator rights**.

```
 ~\src\powershell10k   main ⇡2 !1 ?3                          4s  18:42:07 
❯ git status
```

## Features

- **powerlevel10k style prompt**: rainbow, classic, lean and pure styles;
  sharp, round or slanted heads; one or two lines; right prompt; frame and gap
  fillers; transient prompt; sparse or compact spacing.
- **`p10k configure` wizard** that previews every option in your terminal. It
  starts on its own the first time you open a shell without `~/.p10k.ps1`.
- **Segments**: `os_icon`, `dir`, `git` (branch, ahead/behind, stash, merge or
  rebase state, staged/unstaged/untracked/conflicted counts), `status`,
  `command_execution_time`, `background_jobs`, `virtualenv`, `anaconda`,
  `node_version`, `dotnet_version`, `aws`, `context` (user@host when elevated or
  over SSH), `time`, plus your own.
- **zsh-syntax-highlighting**: the command turns green when it exists and red
  when it doesn't, as you type. Strings, variables, parameters and comments get
  their own colors.
- **History substring search**: type `git`, then press <kbd>Up</kbd>/<kbd>Down</kbd>
  to step through every earlier command that starts with `git`.
- **zsh-autosuggestions**: grey inline suggestions from history with
  PSReadLine 2.1+ (the installer offers a current-user upgrade).
- **oh-my-zsh plugins**: `git` (about 80 aliases plus tab completion), `z`,
  `aliases`, `autosuggestions`, `syntax-highlighting`, `extract`, `web-search`,
  `copypath`.
- `custom/` folder for your own plugins, themes and segments, like `$ZSH_CUSTOM`.

## Install

```powershell
git clone https://github.com/<you>/powershell10k.git
cd powershell10k
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

(A downloaded and unzipped copy works the same way.) Then restart Windows
Terminal. The configuration wizard starts in the first new tab.

### What the installer touches (everything is per-user)

| What | Where |
| --- | --- |
| Framework files | `~\.powershell10k` (`-InstallDir` to change) |
| MesloLGS NF font | `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + `HKCU:\...\Fonts` (Windows 10 1809+) |
| Windows Terminal font | `profiles.defaults.font.face` in its `settings.json`, backup saved next to it |
| Profile | a marked block in `Documents\WindowsPowerShell\` and `Documents\PowerShell\` profiles, backups saved next to them |
| Execution policy | `RemoteSigned` for `CurrentUser`, only if scripts are blocked |
| PSReadLine | optional upgrade with `Install-Module -Scope CurrentUser` |

Nothing goes to Program Files or HKLM, and nothing asks for elevation.

### Installer options

```powershell
.\install.ps1 -Plugins git,z,aliases,autosuggestions,syntax-highlighting
.\install.ps1 -SkipFont -SkipTerminal       # bring your own Nerd Font
.\install.ps1 -UpgradePSReadLine            # upgrade without asking
.\install.ps1 -RepoUrl https://github.com/<you>/powershell10k.git   # git install, enables `ps10k update`
```

## Usage

```
p10k configure     run the wizard again
p10k edit          open ~/.p10k.ps1
p10k segments      list available segments
ps10k plugins      list plugins (* = enabled)
ps10k themes       list themes
ps10k reload       reload after editing config or plugins
ps10k doctor       check font, PSReadLine, git and execution policy
ps10k update       git pull (git installs)
ps10k uninstall    remove from your profile (add -RemoveFiles -RemoveConfig -RemoveFonts)
```

### Enabling plugins

Edit the block in your profile (`notepad $PROFILE`):

```powershell
$global:PS10K_PLUGINS = @('git', 'z', 'aliases', 'autosuggestions', 'syntax-highlighting', 'extract')
```

Keep `syntax-highlighting` after `autosuggestions` so history navigation gets
highlighted too.

### Configuration

`~/.p10k.ps1` overrides the defaults from [lib/config.ps1](lib/config.ps1):

```powershell
$P10K.Style = 'lean'
$P10K.LeftSegments = @('dir', 'git')
$P10K.RightSegments = @('status', 'command_execution_time', 'time')
$P10K.Colors['dir'] = @{ Fg = 255; Bg = 24 }
$P10K.TransientPrompt = $true
```

### Custom segments

```powershell
# custom/segments.ps1
$PS10K_SEGMENTS['hello'] = { param($ctx) @{ IconText = '*'; Text = 'hi'; Fg = 0; Bg = 6 } }
```

## Plugins

| Plugin | What it does |
| --- | --- |
| `git` | `gst`, `ga`, `gaa`, `gc`, `gcmsg`, `gco`, `gcb`, `gd`, `gl`, `gp`, `gpsup`, `glog`, `grb`, `gsta`, `gstp`, `gsw`... and completion for subcommands, branches and remotes. The built-in `gc`, `gl` and `gp` aliases are replaced; `gm` and `gcm` stay `Get-Member`/`Get-Command` unless you set `$PS10K_GIT_OVERRIDE = @('gm','gcm')`. |
| `z` | `z proj` jumps to the most frecent match, `z -l`, `z -x`, `z -c`. |
| `aliases` | `..`, `...`, `ll`, `la`, `take`/`mkcd`, `touch`, `which`, `grep` (if missing), `hs` (search saved history), `path`. |
| `autosuggestions` | prefix history search on Up/Down, menu completion on Tab, inline suggestions (PSReadLine 2.1+). |
| `syntax-highlighting` | live green/red command validation plus a token color palette. |
| `extract` | `extract file.zip` / `x file.tar.gz` |
| `web-search` | `google`, `ddg`, `bing`, `github`, `stackoverflow`, `wiki`, `youtube` |
| `copypath` | `copypath [path]`, `copyfile <file>` |

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

## Credits

Inspired by [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) and
[powerlevel10k](https://github.com/romkatv/powerlevel10k); the MesloLGS NF
font comes from [powerlevel10k-media](https://github.com/romkatv/powerlevel10k-media).
This project is an independent PowerShell implementation.

## License

MIT
