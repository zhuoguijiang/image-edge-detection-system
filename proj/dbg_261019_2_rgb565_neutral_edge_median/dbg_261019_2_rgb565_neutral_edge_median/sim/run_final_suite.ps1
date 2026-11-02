param(
    [string]$VivadoBin = 'D:\for_vivado\Vivado\2022.2\bin'
)

$ErrorActionPreference = 'Stop'
$ver   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root  = (Resolve-Path (Join-Path $ver '..\..\..')).Path
$rtl   = Join-Path $root 'build_repo\rtl\video'
$out   = Join-Path $PSScriptRoot 'logs\final-20261027'
$build = Join-Path $PSScriptRoot 'vivado_build_final'
New-Item -ItemType Directory -Force -Path $out, $build | Out-Null

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim  = Join-Path $VivadoBin 'xsim.bat'

$common = @(
    (Join-Path $rtl 'line_buffer_3x3.v'),
    (Join-Path $rtl 'debayer.v'),
    (Join-Path $rtl 'grayscale.v'),
    (Join-Path $rtl 'sort3.v'),
    (Join-Path $rtl 'video_delay.v'),
    (Join-Path $ver 'median3x3.v'),
    (Join-Path $ver 'gaussian5x5.v'),
    (Join-Path $ver 'gaussian3x3.v'),
    (Join-Path $ver 'sobel.v'),
    (Join-Path $ver 'scharr.v'),
    (Join-Path $ver 'nms3x3.v'),
    (Join-Path $ver 'canny_nms.v'),
    (Join-Path $ver 'canny_nms_interp.v'),
    (Join-Path $ver 'canny_hysteresis.v'),
    (Join-Path $ver 'edge_link3x3.v'),
    (Join-Path $ver 'alg_top.v'),
    (Join-Path $ver 'camera_line_unpack.v'),
    (Join-Path $ver 'video_frame_store.v'),
    (Join-Path $ver 'edge_frame_store.v'),
    (Join-Path $ver 'rgb565_preview_store.v'),
    (Join-Path $ver 'vga_timing.v'),
    (Join-Path $ver 'measurement_timing.v')
)

$tests = @(
    'tb_gaussian5x5',
    'tb_canny_hysteresis',
    'tb_gray_path',
    'tb_camera_line_unpack_ram',
    'tb_rgb565_preview_store',
    'tb_video_frame_store_depth',
    'tb_edge_frame_store_aligned',
    'tb_canny_nms_interp',
    'tb_alg_canny',
    'tb_canny_chain',
    'tb_alg_sobel',
    'tb_gaussian_pos',
    'tb_measurement_timing'
)

$sources = @($common)
foreach ($test in $tests) {
    $sources += (Join-Path $PSScriptRoot ($test + '.v'))
}

Push-Location $build
try {
    & $xvlog @sources *> (Join-Path $out 'suite.xvlog.log')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    & $xvlog -version *> (Join-Path $out 'simulator_version.txt')
    Set-Content -LiteralPath (Join-Path $out 'run_metadata.txt') -Encoding UTF8 -Value @(
        "Run date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        "Simulator: Vivado Simulator 2022.2",
        "Version directory: $ver",
        "Clock for unit tests: testbench-defined"
    )

    $hashLines = foreach ($f in $sources) {
        $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
        "$h  $f"
    }
    Set-Content -LiteralPath (Join-Path $out 'source_sha256.txt') -Encoding UTF8 -Value $hashLines

    $results = @()
    foreach ($test in $tests) {
        & $xelab $test -s $test -relax *> (Join-Path $out ($test + '.xelab.log'))
        if ($LASTEXITCODE -ne 0) {
            $results += [pscustomobject]@{Test=$test; Result='ELAB_FAIL'; Log=$test + '.xelab.log'}
            continue
        }

        & $xsim $test -R *> (Join-Path $out ($test + '.log'))
        $simExit = $LASTEXITCODE
        $text = Get-Content -LiteralPath (Join-Path $out ($test + '.log')) -Raw
        if ($simExit -eq 0 -and $text -match 'PASS:' -and $text -notmatch 'FAIL:') {
            $result = 'PASS'
        } else {
            $result = 'FAIL'
        }
        $results += [pscustomobject]@{Test=$test; Result=$result; Log=$test + '.log'}
    }

    $results | Format-Table -AutoSize | Out-String |
        Set-Content -LiteralPath (Join-Path $out 'summary.txt') -Encoding UTF8
    $results | Export-Csv -LiteralPath (Join-Path $out 'summary.csv') -NoTypeInformation -Encoding UTF8
    $results | Format-Table -AutoSize
    if (($results | Where-Object Result -ne 'PASS').Count -ne 0) { exit 1 }
} finally {
    Pop-Location
}
