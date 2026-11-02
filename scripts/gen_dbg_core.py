#!/usr/bin/env python3
#==============================================================================
# scripts/gen_dbg_core.py - generate the Efinity Debugger core for one project
#
#   The Efinity debugger auto-instantiation flow needs two artifacts that the
#   GUI wizard normally produces:
#
#     <proj>/work_dbg/debug_top.v            the JTAG debug core (debug_hub +
#                                            one LogicN logic analyzer per
#                                            clock domain, with the probes)
#     <proj>/debug_profile.wizard.json       the same profile plus the
#                                            "debug_cores"/"connections"/"vdbs"
#                                            sections that efx_map needs to
#                                            wire the probes to the nets
#
#   This script produces both from a small *selection* file that only lists the
#   nets you want to watch - i.e. it is the command-line equivalent of clicking
#   "Mark Debug" in the Efinity GUI:
#
#     dbg_core.selection.json  --[gen_dbg_core.py]-->  debug_profile.wizard.json
#                                                      work_dbg/debug_top.v
#
#   It does NOT need the design netlist: the wizard derives the probe ports from
#   the selection (name + width + clock domain) alone.  Afterwards a normal
#   project build (scripts\build.ps1, or the Efinity GUI) picks the core up
#   through the <efx:debugger> section of the project XML and produces the
#   debug-enabled bitstream in one go.
#
# HOW TO RUN (must use the Efinity python, PYTHONHOME set - build.ps1 shows the
# environment, or use scripts\build.ps1 which does it for you):
#
#   $efx = 'F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1'
#   $env:PYTHONHOME = "$efx\python311"
#   & "$efx\python311\bin\python.exe" scripts\gen_dbg_core.py `
#         proj\dbg_20260924_01\dbg_core.selection.json
#
#   The selection file is never modified; the wizard profile is rewritten every
#   run, so the selection file stays the single source of truth.
#==============================================================================
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

DEFAULT_EFX = r"F:\WORK\My_Efinity\efinity-2026.1.132-windows-x64\efinity\2026.1"


def efx_root() -> Path:
    home = os.environ.get("EFINITY_HOME") or DEFAULT_EFX
    return Path(home.replace("\\", "/"))


class Args:
    """The attribute bag gen_debug_v_from_profile() expects."""

    def __init__(self, debug_profile, work_dir, family, device, log_file):
        self.debug_profile = str(debug_profile)
        self.work_dir = Path(work_dir)
        self.family = family
        self.device = device
        self.LOG_FILE = str(log_file)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Generate the Efinity debugger core (debug_top.v) and the "
                    "debugger wizard profile from a net selection file.")
    ap.add_argument("selection", type=Path,
                    help="dbg_core.selection.json (session.wizard.selected_nets)")
    ap.add_argument("--out", type=Path, default=None,
                    help="wizard profile to (re)write "
                         "(default: <dir>/debug_profile.wizard.json)")
    ap.add_argument("--work_dir", type=Path, default=None,
                    help="where debug_top.v is written (default: <dir>/work_dbg)")
    ap.add_argument("--family", default="Titanium")
    ap.add_argument("--device", default="Ti60F225")
    args = ap.parse_args()

    selection = args.selection.resolve()
    if not selection.is_file():
        raise SystemExit(f"selection file not found: {selection}")

    proj_dir = selection.parent
    out_profile = (args.out or (proj_dir / "debug_profile.wizard.json")).resolve()
    work_dir = (args.work_dir or (proj_dir / "work_dbg")).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    # The wizard rewrites the profile in place, so start from a fresh copy of
    # the (hand written) selection.
    shutil.copyfile(selection, out_profile)

    root = efx_root()

    # efx_dbg.rtl_gen reads these at import time and then assembles the debug
    # core from <EFXDBG_HOME>/rtl/{common,LogicN,VIO}.
    os.environ.setdefault("EFXDBG_HOME", str(root / "debugger"))
    os.environ.setdefault("EFINITY_HOME", root.as_posix())

    dbg_bin = root / "debugger" / "bin"
    sys.path.append(str(dbg_bin))
    try:
        from efx_dbg.DbgWizard import gen_debug_v_from_profile
    except ImportError as exc:
        raise SystemExit(
            f"cannot import the Debug Wizard ({exc}).\n"
            f"Run this script with the Efinity python and PYTHONHOME set:\n"
            f"  $env:PYTHONHOME = '{root / 'python311'}'\n"
            f"  & '{root / 'python311' / 'bin' / 'python.exe'}' "
            f"{Path(__file__).name} {args.selection}")

    log_file = work_dir / "gen_dbg_core.log"
    rc = gen_debug_v_from_profile(
        Args(out_profile, work_dir, args.family, args.device, log_file))

    if not (work_dir / "debug_top.v").is_file():
        raise SystemExit("debug_top.v was not generated - check the selection")

    profile = json.loads(out_profile.read_text(encoding="utf-8"))
    cores = profile.get("debug_cores", [])
    print(f"wizard profile : {out_profile}")
    print(f"debug core rtl : {work_dir / 'debug_top.v'}")
    print(f"debug cores    : {[c.get('name') for c in cores]}")
    for core in cores:
        probes = ", ".join(f"{p['name']}[{p['width']}]" for p in core["probes"])
        print(f"  {core['name']}: {probes}")
    if not cores:
        print("WARNING: no debug cores were created (empty selection?)")
    if rc == 3:
        print("WARNING: LogicN design-limit warning (probe id >= 63?)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
