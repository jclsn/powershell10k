# The powerlevel10k theme: segments, rendering, prompt, wizard.
# Dot-sourced by run-tests.ps1, which provides $root, $work and the asserts.

Test-Case 'duration formatting' {
    Assert-Equal '4s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 0)
    Assert-Equal '4.70s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(4.7)) 2)
    Assert-Equal '1m 5s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(65)) 0)
    Assert-Equal '1h 0m 1s' (_ps10k_format_duration ([TimeSpan]::FromSeconds(3601)) 0)
}

Test-Case 'long paths are shortened in the middle' {
    $long = 'C:\Users\someone\projects\.config\very-long-directory-name\leaf'
    Assert-Equal 'C:\U\s\p\.config\very-long-directory-name\leaf' ((_ps10k_shorten_path $long 46 '\') -join '\')
    Assert-Equal 'C:\U\s\p\.c\v\leaf' ((_ps10k_shorten_path $long 10 '\') -join '\')
    $parts = _ps10k_shorten_path 'C:\short' 30 '\'
    Assert-Equal 'C:\short' ($parts -join '\')
}

Test-Case 'prompt renders in every style and layout' {
    foreach ($style in 'rainbow', 'classic', 'lean', 'pure') {
        foreach ($multi in $true, $false) {
            $P10K.Style = $style; $P10K.MultiLine = $multi
            $text = prompt
            Assert-True ($text -match 'tests|powershell10k') "style $style missing directory"
            Assert-True ($text -notmatch '^PS ') "style $style fell back to the plain prompt: $($global:_ps10k_state.PromptError)"
        }
    }
    _ps10k_load_config
}

Test-Case 'two-line prompt fills the first line to the terminal width' {
    $left = @(@{ Name = 'dir'; Icon = 'folder'; Text = 'C:\x' })
    $right = @(@{ Name = 'time'; Icon = 'time'; Text = '12:00:00' })
    foreach ($gap in 'none', 'dot', 'line') {
        $P10K.Gap = $gap
        $text = _ps10k_render_prompt -Left $left -Right $right -Width 80
        $line1 = ($text -split "`n")[1]
        Assert-Equal 79 (_ps10k_width $line1) "gap $gap"
    }
    _ps10k_load_config
}

Test-Case 'status segment shows the exit code' {
    $seg = & $global:PS10K_SEGMENTS['status'] @{ Success = $false; ExitCode = 2 }
    Assert-Equal '2' $seg.Text
    Assert-Equal 'error' $seg.State
    Assert-True ($null -eq (& $global:PS10K_SEGMENTS['status'] @{ Success = $true; ExitCode = 0 }))
}

Test-Case 'prompt preserves LASTEXITCODE' {
    $global:LASTEXITCODE = 7
    $null = prompt
    Assert-Equal 7 $global:LASTEXITCODE
}

Test-Case 'configure writes a config that loads back' {
    $answers = [ordered]@{ Mode = 'unicode'; Style = 'lean'; MultiLine = $false; RightSegments = @('status', 'time'); TransientPrompt = $true }
    Set-Content -LiteralPath $env:PS10K_CONFIG -Value (_ps10k_wizard_config_text $answers) -Encoding UTF8
    _ps10k_load_config
    Assert-Equal 'lean' $P10K.Style
    Assert-Equal 'unicode' $P10K.Mode
    Assert-Equal $false $P10K.MultiLine
    Assert-Equal 'status time' "$($P10K.RightSegments)"
    Remove-Item -LiteralPath $env:PS10K_CONFIG
    _ps10k_load_config
}
