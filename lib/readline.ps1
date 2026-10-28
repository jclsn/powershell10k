# PSReadLine internals for things its public API cannot tell: where the
# command line is on screen. Used by the completion grid (autosuggestions) and
# by syntax-highlighting. Every caller copes with $null (internals missing).

# Reflection handles, or $null.
function global:_ps10k_rl_internals {
    if ($global:_ps10k_rl) { return $global:_ps10k_rl }
    try {
        $type = [Microsoft.PowerShell.PSConsoleReadLine]
        $flags = [Reflection.BindingFlags]'NonPublic, Instance'
        $singleton = $type.GetField('_singleton', [Reflection.BindingFlags]'NonPublic, Static').GetValue($null)
        $rl = @{
            Singleton      = $singleton
            InitialY       = $type.GetField('_initialY', $flags)
            PreviousRender = $type.GetField('_previousRender', $flags)
            EndOfBuffer    = $type.GetMethod('EndOfBufferPosition', $flags)
        }
        if (-not ($singleton -and $rl.InitialY -and $rl.PreviousRender -and $rl.EndOfBuffer)) { return $null }
        $render = $rl.PreviousRender.GetValue($singleton)
        if (-not $render) { return $null }
        $rl.RenderInitialY = $render.GetType().GetField('initialY')
        $rl.RenderCursorTop = $render.GetType().GetField('cursorTop')
        $point = $rl.EndOfBuffer.ReturnType
        $rl.PointX = $point.GetField('X')
        $rl.PointY = $point.GetField('Y')
        if (-not ($rl.RenderInitialY -and $rl.RenderCursorTop -and $rl.PointX -and $rl.PointY)) { return $null }
        $global:_ps10k_rl = $rl
        $rl
    }
    catch { $null }
}

# Screen position just after the last character of the command line.
function global:_ps10k_rl_end_point($Rl) {
    $point = $Rl.EndOfBuffer.Invoke($Rl.Singleton, @())
    @{ X = [int]$Rl.PointX.GetValue($point); Y = [int]$Rl.PointY.GetValue($point) }
}
