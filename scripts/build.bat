@echo off
setlocal

REM ============================================================
REM  Efinity one-shot full-flow build wrapper (no manual env vars)
REM
REM  Usage (from repo root):
REM      scripts\build.bat [path\to\project.xml]
REM  If no project is given, defaults to proj\colorbar\colorbar.xml.
REM ============================================================

REM Auto-detect the Efinity install; override by setting EFINITY_ROOT first.
if not defined EFINITY_ROOT (
    if exist "D:\for_efinity\efinity\2026.1\bin\setup.bat" set "EFINITY_ROOT=D:\for_efinity\efinity\2026.1"
)
if not defined EFINITY_ROOT (
    if exist "F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1\bin\setup.bat" set "EFINITY_ROOT=F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1"
)
if not defined EFINITY_ROOT (
    echo ERROR: Efinity not found. Set EFINITY_ROOT to your ...\efinity\2026.1 directory.
    exit /b 1
)

set "PROJECT=%1"
if "%PROJECT%"=="" set "PROJECT=proj\colorbar\colorbar.xml"

REM Set up the Efinity toolchain environment in this session
REM (PATH, EFINITY_HOME, PYTHONHOME, EFX*_HOME, EFINITY_USER_DIR_INI, ...).
call "%EFINITY_ROOT%\bin\setup.bat"
if errorlevel 1 exit /b %errorlevel%

REM Resolve the project path and switch to its directory. Efinity resolves
REM design files, colorbar.peri.xml and outflow/ relative to the project dir.
for %%I in ("%PROJECT%") do (
    set "PROJECT_ABS=%%~fI"
    set "PROJECT_DIR=%%~dpI"
    set "PROJECT_NAME=%%~nxI"
)
cd /d "%PROJECT_DIR%"

REM Efinity expects outflow/ to already exist.
if not exist "outflow" mkdir "outflow"

"%EFINITY_ROOT%\python311\bin\python.exe" "%EFINITY_ROOT%\scripts\efx_run.py" "%PROJECT_NAME%"
exit /b %ERRORLEVEL%
