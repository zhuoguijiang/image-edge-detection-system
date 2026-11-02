#==============================================================================
# scripts/build_dbg_core.ps1 - (re)generate the Efinity debugger core
#
#   Wraps scripts\gen_dbg_core.py with the environment it needs (Efinity python
#   + PYTHONHOME + EFXDBG_HOME), so the debug core can be regenerated from the
#   net selection file without opening the Efinity GUI.
#
#   Usage (from the repository root):
#
#       scripts\build_dbg_core.ps1
#       scripts\build_dbg_core.ps1 -Selection proj\dbg_20260924_01\dbg_core.selection.json
#
#   Output (next to the selection file):
#       debug_profile.wizard.json    debug cores + probe -> net connections
#       work_dbg\debug_top.v         the JTAG debug core RTL
#
#   The following project build (scripts\build.ps1 <project>.xml) then compiles
#   those into the bitstream through the <efx:debugger> section.
#==============================================================================
param(
    [string] $Selection   = 'proj\dbg_20260924_01\dbg_core.selection.json',
    [string] $EfinityHome = $env:EFINITY_HOME
)

$ErrorActionPreference = 'Stop'

function Resolve-EfinityRoot {
    param([string] $Hint)
    $candidates = @()
    if ($Hint) { $candidates += $Hint }
    $candidates += @(
        'D:\for_efinity\efinity\2026.1',
        'C:\efinity\2026.1',
        'F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath "$c\bin\efx_map.exe")) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    throw "Efinity not found. Pass -EfinityHome <dir> or set `$env:EFINITY_HOME."
}

$root    = Split-Path -Parent $PSScriptRoot
$efxRoot = Resolve-EfinityRoot -Hint $EfinityHome
$pyPath  = Join-Path $efxRoot 'python311\bin\python.exe'

if (-not (Test-Path -LiteralPath $pyPath)) { throw "Efinity python not found: $pyPath" }

$env:PYTHONHOME  = Join-Path $efxRoot 'python311'
$env:EFXDBG_HOME = Join-Path $efxRoot 'debugger'
$env:EFINITY_HOME = ($efxRoot -replace '\\', '/')

$selFull = (Resolve-Path -LiteralPath (Join-Path $root $Selection)).Path

Write-Host "Efinity root : $efxRoot"
Write-Host "selection    : $selFull"

& $pyPath (Join-Path $root 'scripts\gen_dbg_core.py') $selFull
exit $LASTEXITCODE
