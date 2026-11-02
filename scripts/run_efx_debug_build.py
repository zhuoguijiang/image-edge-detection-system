import os
import sys
import runpy
import importlib.util


EFX = r"F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1"
EFX_UNIX = EFX.replace("\\", "/")

USER_DIR = r"G:\NJU\Codex_FPGA\tmp\efinity_debug\user"
USER_DIR_INI = r"G:\NJU\Codex_FPGA\tmp\efinity_debug\user_dir.ini"

os.makedirs(USER_DIR, exist_ok=True)

os.environ["EFINITY_HOME"] = EFX_UNIX
os.environ["PYTHONHOME"] = os.path.join(EFX, "python311")
os.environ["EFXPT_HOME"] = EFX_UNIX + "/pt"
os.environ["EFXPGM_HOME"] = EFX_UNIX + "/pgm"
os.environ["EFXDBG_HOME"] = EFX_UNIX + "/debugger"
os.environ["EFXIPM_HOME"] = EFX_UNIX + "/ipm"
os.environ["EFXSVF_HOME"] = EFX_UNIX + "/debugger/svf_player"
os.environ["EFXSERDESDBG_HOME"] = EFX_UNIX + "/debugger/serdes_debug_tool"
os.environ["EFINITY_USER_DIR"] = USER_DIR
os.environ["EFINITY_USER_DIR_INI"] = USER_DIR_INI

efx_path_entries = [
    os.path.join(EFX, "python311", "bin"),
    os.path.join(EFX, "bin"),
    os.path.join(EFX, "pgm", "bin"),
    os.path.join(EFX, "debugger", "bin"),
    os.path.join(EFX, "scripts"),
    os.path.join(EFX, "ipm", "bin", "ip_packager"),
]
os.environ["PATH"] = os.pathsep.join(efx_path_entries + [os.environ.get("PATH", "")])

import shutil

_original_which = shutil.which

def _patched_which(cmd, mode=os.F_OK | os.X_OK, path=None):
    if cmd == "efx_map.exe":
        return os.path.join(EFX, "bin", "efx_map.exe")
    return _original_which(cmd, mode, path)

shutil.which = _patched_which

for path in [
    os.path.join(EFX, "scripts"),
    os.path.join(EFX, "debugger", "bin"),
    os.path.join(EFX, "pgm", "bin"),
]:
    sys.path.insert(0, path)

sys.path.insert(0, r"G:\NJU\Codex_FPGA\scripts")

local_dbg = os.path.join(r"G:\NJU\Codex_FPGA\scripts", "efx_run_dbg.py")
spec = importlib.util.spec_from_file_location("efx_run_dbg", local_dbg)
local_dbg_module = importlib.util.module_from_spec(spec)
sys.modules["efx_run_dbg"] = local_dbg_module
spec.loader.exec_module(local_dbg_module)

project = sys.argv[1] if len(sys.argv) > 1 else r"proj\system\system_dbg.xml"
sys.argv = ["efx_run.py", project]

try:
    runpy.run_path(os.path.join(EFX, "scripts", "efx_run.py"), run_name="__main__")
except SystemExit as exc:
    sys.exit(exc.code)
