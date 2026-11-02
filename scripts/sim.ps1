# scripts/sim.ps1
# Usage (run from the project root):
#   scripts\sim.ps1 <top_module> <source files...>
# Example:
#   scripts\sim.ps1 tb_vga_timing rtl/display/vga_timing.v sim/tb_vga_timing.v
$ErrorActionPreference = 'Stop'

$iverilogHome = $env:IVERILOG_HOME
if (-not $iverilogHome) {
    foreach ($c in @('F:\WORK\IcarusVerilog\iverilog',
                     'C:\iverilog',
                     'D:\iverilog',
                     'C:\Program Files\iverilog')) {
        if (Test-Path -LiteralPath (Join-Path $c 'bin\iverilog.exe')) { $iverilogHome = $c; break }
    }
}
if (-not $iverilogHome) {
    $cmd = Get-Command iverilog -ErrorAction SilentlyContinue
    if ($cmd) { $iverilogHome = Split-Path -Parent (Split-Path -Parent $cmd.Source) }
}
if (-not $iverilogHome) {
    Write-Error "Icarus Verilog not found. Set `$env:IVERILOG_HOME to your iverilog directory."
    exit 1
}
$env:Path = "$iverilogHome\bin;$env:Path"

if ($args.Count -lt 2) {
    Write-Host "Usage: scripts\sim.ps1 <top_module> <source files...>"
    exit 2
}

$top  = $args[0]
$srcs = $args[1..($args.Count - 1)]
$out  = Join-Path 'sim' ($top + '.vvp')

& "$iverilogHome\bin\iverilog.exe" -g2005 -s $top -o $out @srcs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& "$iverilogHome\bin\vvp.exe" $out
exit $LASTEXITCODE
