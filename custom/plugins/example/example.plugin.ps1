# Example plugin. Enable it by adding 'example' to $PS10K_PLUGINS.

function global:hello { Write-Host "Hello from a powershell10k custom plugin, $env:USERNAME!" }
