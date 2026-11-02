#==============================================================================
# scripts/build.ps1 - one-shot Efinity full-flow build
#
#   Usage (from the repo root):
#       scripts\build.ps1 [path\to\project.xml]
#   Default project: proj\colorbar\colorbar.xml
#
# WHY THE MIRROR STEP EXISTS
#   Efinity 2026.1 refuses to run from a directory whose path contains
#   non-ASCII characters: efx_map and efx_pt survive, but efx_pnr aborts with
#       "'gbk' codec can't decode byte 0x.. in position ..."
#   and the flow prints
#       "The following paths contain non-ASCII characters ... Please move the
#        project on a directory path with only ASCII characters."
#   This repository lives under "作业工作台", so when that happens the script
#   mirrors the *sources* into an ASCII scratch tree under %TEMP%, runs the
#   whole flow there, and copies the results back into the real outf>low/.
#   Use -NoMirror to disable, or just move the repo to an ASCII path
#   (e.g. D:\NJU\Codex_FPGA) - that is the recommended long-term fix.
#
# The Efinity installation is auto-detected; override with -EfinityHome or by
# setting $env:EFINITY_HOME.
#==============================================================================
param(
    [string] $Project     = 'proj\colorbar\colorbar.xml',
    [string] $EfinityHome = $env:EFINITY_HOME,
    [switch] $NoMirror
)

$ErrorActionPreference = 'Stop'

function Resolve-EfinityRoot {
    param([string]$Hint)

    $candidates = @()
    if ($Hint) { $candidates += $Hint }
    $candidates += @(
        'D:\for_efinity\efinity\2026.1',
        'C:\efinity\2026.1',
        'F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1'
    )

    foreach ($c in $candidates) {
        # NB: string concat, not Join-Path -- Join-Path throws on a drive letter
        # that does not exist on this machine (e.g. the D:\ candidate).
        if ($c -and (Test-Path -LiteralPath "$c\bin\efx_map.exe")) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }

    foreach ($drive in @('C:','D:','E:','F:','G:')) {
        if (-not (Test-Path "$drive\")) { continue }
        $hit = Get-ChildItem -Path "$drive\" -Filter 'efx_map.exe' -Recurse `
                             -ErrorAction SilentlyContinue -Depth 6 |
               Where-Object { $_.FullName -match '\\bin\\efx_map\.exe$' } |
               Select-Object -First 1
        if ($hit) { return (Split-Path -Parent (Split-Path -Parent $hit.FullName)) }
    }

    throw "Efinity not found. Pass -EfinityHome <dir> or set `$env:EFINITY_HOME."
}

function Test-NonAscii {
    param([string]$Path)
    foreach ($ch in $Path.ToCharArray()) { if ([int]$ch -gt 127) { return $true } }
    return $false
}

function Get-RepoRoot {
    param([string]$ProjectFull)
    # <root>\proj\<name>\<name>.xml  ->  <root>
    $projDir = Split-Path -Parent $ProjectFull
    return (Split-Path -Parent (Split-Path -Parent $projDir))
}

#==============================================================================
# 1. Resolve project, Efinity root and (optionally) an ASCII mirror
#==============================================================================
$projFull = (Resolve-Path -LiteralPath $Project).Path
$projDirReal = Split-Path -Parent $projFull
$projName    = Split-Path -Leaf $projFull
$repoRoot    = Get-RepoRoot -ProjectFull $projFull

$efxRoot = Resolve-EfinityRoot -Hint $EfinityHome

Write-Host "Efinity root : $efxRoot"
Write-Host "Repository   : $repoRoot"
Write-Host "Project      : $projFull"

$mirrorRepo = $null
if ((Test-NonAscii $projFull) -and (-not $NoMirror)) {
    $mirrorRoot = Join-Path $env:TEMP 'efx_build'
    $mirrorRepo = Join-Path $mirrorRoot (Split-Path -Leaf $repoRoot)
    New-Item -ItemType Directory -Force -Path $mirrorRoot | Out-Null

    Write-Host "Non-ASCII path detected -> mirroring sources to $mirrorRepo"
    Write-Host "  (Efinity place-and-route cannot run from a non-ASCII directory)"

    # Mirror everything except build artifacts and the bulky IP test benches.
    $xd = @('outflow','work_syn','work_pnr','Testbench','modelsim','ncsim',
            'synopsys','.git','.code')
    $rcArgs = @($repoRoot, $mirrorRepo, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS',
                '/R:2', '/W:1', '/XD') + $xd
    & robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

    $projRel    = $projFull.Substring($repoRoot.Length).TrimStart('\')
    $projFull   = Join-Path $mirrorRepo $projRel
    $projDirReal = Split-Path -Parent (Join-Path $repoRoot $projRel)
    Write-Host "Building in  : $projFull"
}

$projDir = Split-Path -Parent $projFull

#==============================================================================
# 2. Environment (replicates <efinity>\bin\setup.bat)
#==============================================================================
$efxBin  = "$efxRoot\bin"
$efxUnix = $efxRoot -replace '\\','/'

$env:EFINITY_BINPATH   = "$efxBin\"
$env:EFINITY_HOME      = $efxUnix
$env:PYTHONHOME        = "$efxRoot\python311"
$env:EFXPT_HOME        = "$efxUnix/pt"
$env:EFXPGM_HOME       = "$efxUnix/pgm"
$env:EFXDBG_HOME       = "$efxUnix/debugger"
$env:EFXIPM_HOME       = "$efxUnix/ipm"
$env:EFXSVF_HOME       = "$efxUnix/debugger/svf_player"
$env:EFXSERDESDBG_HOME = "$efxUnix/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI = "$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:QT_LOGGING_CONF   = "$efxBin\lc.ini"
$env:QT_PLUGIN_PATH    = "$efxUnix/bin"
$env:QT_QPA_PLATFORM_PLUGIN_PATH = "$efxUnix/python311/platforms"
$env:QTWEBENGINE_CHROMIUM_FLAGS = '--disable-gpu'
$env:PATH = "$efxRoot\python311\bin;$efxBin;$efxRoot\pgm\bin;$efxRoot\debugger\bin;" +
            "$efxRoot\debugger\svf_player\bin;$efxRoot\debugger\serdes_debug_tool\bin;" +
            "$efxRoot\scripts;$efxRoot\ipm\bin\ip_packager;$env:PATH"

#==============================================================================
# 3. Run the flow
#==============================================================================
Push-Location $projDir
try {
    New-Item -ItemType Directory -Force -Path 'outflow' | Out-Null
    & "$efxRoot\python311\bin\python.exe" "$efxRoot\scripts\efx_run.py" $projName
    $rc = $LASTEXITCODE
} finally {
    Pop-Location
}

#==============================================================================
# 4. Copy the results back when building from a mirror
#==============================================================================
if ($mirrorRepo) {
    $srcOut = Join-Path $projDir 'outflow'
    $dstOut = Join-Path $projDirReal 'outflow'
    if ($rc -eq 0 -and (Test-Path -LiteralPath $srcOut)) {
        New-Item -ItemType Directory -Force -Path $dstOut | Out-Null
        Copy-Item -Path (Join-Path $srcOut '*') -Destination $dstOut -Recurse -Force
        Write-Host "Results copied back to $dstOut"
    } else {
        Write-Host "Build failed (rc=$rc); nothing copied back."
    }
}

exit $rc
