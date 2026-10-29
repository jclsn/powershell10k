# The z and vi-mode plugins.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'z ranks visited directories' {
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\alpha\project'
    _ps10k_z_add 'C:\beta\project'
    $found = _ps10k_z_matches -Terms @('project')
    Assert-Equal 'C:\alpha\project' $found[0].Path
    Assert-Equal 1 @(_ps10k_z_matches -Terms @('beta')).Count
}

Test-Case 'vi-mode switches PSReadLine and redraws the prompt char' {
    if (-not (Get-Module PSReadLine)) { throw 'PSReadLine missing' }
    $plugins = $global:PS10K_PLUGINS
    try {
        $global:PS10K_PLUGINS = @('syntax-highlighting', 'vi-mode')
        $warnings = . (Join-Path $root 'powershell10k.ps1') 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        if ($warnings) { throw "warnings: $($warnings -join '; ')" }
        Assert-Equal 'Vi' (Get-PSReadLineOption).EditMode
        $commandKeys = @(Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq '<k>' })
        Assert-Equal 'PS10kHistorySearchBackward' $commandKeys[0].Function 'k searches history (wrapped by syntax-highlighting)'
        $P10K.MultiLine = $true
        [void](prompt)
        $global:_ps10k_state.ViMode = 'Command'
        $global:_ps10k_state.ViRedraw = $true
        $redrawn = prompt
        Assert-True $redrawn.StartsWith($global:_ps10k_state.LastPrompt.Head) 'redraw changed the prompt body'
        Assert-True $redrawn.Contains((_ps10k_icon 'prompt_vicmd')) 'command mode prompt char missing'
        Assert-True (-not (prompt).Contains((_ps10k_icon 'prompt_vicmd'))) 'a new prompt starts in insert mode'
    }
    finally {
        $global:PS10K_PLUGINS = $plugins
        . (Join-Path $root 'powershell10k.ps1') 3>$null
    }
    Assert-Equal 'Windows' (Get-PSReadLineOption).EditMode 'reload without vi-mode'
}
