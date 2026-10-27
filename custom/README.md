# custom

Your own additions, like `$ZSH_CUSTOM` in oh-my-zsh. The installer never
overwrites this folder.

- `*.ps1` files directly in here are loaded after `lib/`, before plugins.
- `plugins/<name>/<name>.plugin.ps1` adds a plugin, or overrides a bundled
  one with the same name. Enable it in `$PS10K_PLUGINS` in your profile.
- `themes/<name>.theme.ps1` adds a theme. Select it with `$PS10K_THEME`.

Define functions as `function global:name` and aliases with
`Set-Alias -Scope Global`, because `ps10k reload` loads files from inside a
function.

## Custom prompt segments

```powershell
# custom/segments.ps1
$PS10K_SEGMENTS['hello'] = {
    param($ctx)
    @{ IconText = '*'; Text = "hi $env:USERNAME"; Fg = 0; Bg = 6 }
}
```

Then add `'hello'` to `$P10K.LeftSegments` or `$P10K.RightSegments` in
`~/.p10k.ps1`.
