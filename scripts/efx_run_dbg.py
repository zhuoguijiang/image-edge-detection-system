#!/usr/bin/env python3

import argparse
import os
import sys
import platform
import shutil
from pathlib import Path
import json
from functools import reduce
import subprocess
import time
from efx_run_common import HelpFormatter

if platform.system() == "Windows":
	EFX_MAP_PROG='efx_map.exe'
	EFX_PYTHON_RUNTIME='python.exe'
else:
	EFX_MAP_PROG='efx_map'
	EFX_PYTHON_RUNTIME='python3'

EFX_PT_JTAG_UTIL_PROG='efx_pt_jtag_util.py'
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))


def run_proc(exec_cmd=None, timeout=None):
	if exec_cmd is None:
		return None

	process = subprocess.run(exec_cmd,
			stdout=sys.stdout, stderr=sys.stderr, shell=False, timeout=timeout)

	return process.returncode if process else None

def compile_dbg_core(device_family: str, device_model: str,
		output_vdb_file: Path,
		work_dir: Path, output_dir: Path, map_opts: list = [], timeout=None):

	EFX_INSTALL_PATH = Path(os.environ['EFINITY_HOME'])

	efx_prog = EFX_INSTALL_PATH.joinpath(f'bin', f'{EFX_MAP_PROG}')

	DEBUG_TOP_RTL = f'debug_top.v'

	dbg_src_file = work_dir.joinpath(f'{DEBUG_TOP_RTL}')
	if not dbg_src_file.is_file():
		raise FileNotFoundError(f'No such file: {dbg_src_file}')
		return None

	# add --gen-mark-debug-json 0, so that the json file will not be removed
	cmd = [ efx_prog.resolve().as_posix() ]
	cmd.extend([f'--family', f'{device_family}',
		f'--device', f'{device_model}',
		f'--root', f'edb_top',
		f'--v', f'{dbg_src_file.resolve().as_posix()}',
		f'--write-postmap-module', f'{output_vdb_file.resolve().as_posix()}',
		f'--work-dir', f'{work_dir}',
		f'--output-dir', f'{output_dir}',
		f'--gen-mark-debug-json=0'])

	cmd.extend(map_opts)

	print(f'Compile Debugger Core: {" ".join(cmd)}')
	ret_code = run_proc(cmd, timeout)
	if ret_code is not None:
		if ret_code != 0 or not output_vdb_file.is_file():
			raise RuntimeError(f'Fail to compile debug top: {dbg_src_file}')
			return None

	return ret_code

def merge_vdb(device_family, device_model,
		design_vdb_file: Path, debug_top_vdb: Path, top_module: str,
		profile_file: str, output_vdb_file: Path, output_rtl_file: Path,
		work_dir: Path, output_dir: Path,
		map_opts: list = [], timeout=None):

	EFX_INSTALL_PATH = Path(os.environ['EFINITY_HOME'])

	efx_prog = EFX_INSTALL_PATH.joinpath(f'bin', f'{EFX_MAP_PROG}')

	if not design_vdb_file.is_file():
		raise FileNotFoundError(f'No such file: {design_vdb_file}')
		return None

	if not debug_top_vdb.is_file():
		raise FileNotFoundError(f'No such file: {debug_top_vdb}')
		return None

	cmd = [ efx_prog.resolve().as_posix() ]

	if top_module:
		cmd.extend([f'--root', f'{top_module}'])

	# add --gen-mark-debug-json 0, so that the json file will not be removed
	cmd.extend([f'--family', f'{device_family}',
		f'--device', f'{device_model}',
		f'--vdb', f'{design_vdb_file.resolve().as_posix()}',
		f'--vdb', f'{debug_top_vdb.resolve().as_posix()}',
		f'--write-efx-verilog', f'{output_rtl_file.resolve().as_posix()}',
		f'--binary-db', f'{output_vdb_file.resolve().as_posix()}',
		f'--merge_vdbs=1',
		f'--conn', f'{profile_file}',
		f'--work-dir', f'{work_dir}',
		f'--output-dir', f'{output_dir}',
		f'--gen-mark-debug-json=0'])

	cmd.extend(map_opts)

	print(f'Merge VDB: {" ".join(cmd)}')
	ret_code = run_proc(cmd, timeout)
	if ret_code is not None:
		if ret_code != 0 or not output_rtl_file.is_file() \
				or not output_vdb_file.is_file():
			raise RuntimeError(f'Fail to merge design and debug top VDB files: {design_vdb_file} {debug_top_vdb}')
			return None

	return ret_code

def insert_jtag(design_name: str, device_model: str,
		peri_xml_file: Path, jtag_user: str,
		output_peri_xml_file: Path, timeout=None):

	EFX_INSTALL_PATH = Path(os.environ['EFINITY_HOME'])

	efx_prog = EFX_INSTALL_PATH.joinpath(f'scripts', f'{EFX_PT_JTAG_UTIL_PROG}')
	if not efx_prog.is_file():
		return None

	if output_peri_xml_file.is_file():
		output_peri_xml_file.unlink()

	cmd = [ EFX_PYTHON_RUNTIME, efx_prog.resolve().as_posix(),
			f'--device', f'{device_model}',
			f'--project', f'{design_name}',
			f'--design_file', f'{peri_xml_file.resolve().as_posix()}',
			f'--action', f'add',
			f'--jtag_user', f'JTAG_{jtag_user}',
			f'--output', f'{output_peri_xml_file.resolve().as_posix()}']

	print(f'Insert JTAG: {" ".join(cmd)}')
	ret_code = run_proc(cmd, timeout)
	if ret_code is not None:
		if ret_code != 0 or not output_peri_xml_file.is_file():
			raise RuntimeError(f'Fail to enable JTAG core')
			return None

	return ret_code

def parse_debug_profile(profile_jsonfile: Path):
	if profile_jsonfile is None or not profile_jsonfile.is_file():
		return None

	with open(profile_jsonfile, 'r') as fd:
		profile = json.load(fd)

	wizard_info = reduce(lambda d, key: d.get(key, None) if isinstance(d, dict) else None,
			['session', 'wizard'], profile)
	if wizard_info is None:
		return None

	is_postmap = (wizard_info.get('src') == 'postmap')
	top_module = wizard_info.get('top_module', '')
	jtag_user = wizard_info.get('jtag_user', 'USER1')

	return top_module, is_postmap, jtag_user

def check_arg_file_exist(arg):
	value = Path(arg)
	if not value.is_file():
		raise argparse.ArgumentTypeError(f'input file does not exist (file:{value})')
	return value

def parse_cmd_args():
	arg_parser = argparse.ArgumentParser(
			description='''Efx debugger auto instantiation script''',
            formatter_class=HelpFormatter)

	arg_parser.add_argument('design', metavar='design name',
			nargs=1, type=str,
			help='the design name')
	arg_parser.add_argument('--family', type=str, required=True,
			help='the device family')
	arg_parser.add_argument('--device', type=str, required=True,
			help='the device model')
	arg_parser.add_argument('--debug_profile', type=Path, required=True,
			help='specify the debugger profile JSON file')
	arg_parser.add_argument('--top_module', type=str,
			help='specify the top module for synthesis')
	arg_parser.add_argument('--mark_debug', type=Path, default=None,
			help='specify mark_debug work-flow')
	arg_parser.add_argument('--src_dir', type=Path,
			default=Path.cwd(),
			help='the source/project directory (default: %(default)s)')
	arg_parser.add_argument('--work_dir', type=Path, default=None,
			help='the work directory (default: SRC_DIR/work_dbg)')
	arg_parser.add_argument('--output_dir', type=Path, default=None,
			help='the output directory (default: SRC_DIR/outflow)')
	arg_parser.add_argument('--map_opts', nargs='+', action='extend', default=list(),
			help='additional efx_map options')
	arg_parser.add_argument('--timeout', type=int, default=None, 
			help='timeout in seconds, default no timeout')

	args = arg_parser.parse_args()

	check_arg_file_exist(args.debug_profile)

	if args.work_dir is None:
		args.work_dir = args.src_dir.joinpath('work_dbg')

	if args.output_dir is None:
		args.output_dir = args.src_dir.joinpath('outflow')

	return args

# Utility function to set timeout value passed to subprocess call
def calculate_timeout(args):
	if args.timeout is not None:
		assert(args.start_time is not None)
		time_elapsed = time.monotonic() - args.start_time
		return max(0, int(args.timeout-time_elapsed))
	else:
		return None

def process_mark_debug(args):
	dbwdir = os.path.join(SCRIPT_DIR, '..', 'debugger', 'bin')
	sys.path.append(dbwdir)

	try:
		from efx_dbg.DbgWizard import gen_debug_v_from_profile 
	except ImportError:
		with open(args.LOG_FILE, 'a') as f:
			print('Warning: Failed to import Debug Wizard script', file=f)
			print('Warning: Mark Debug', file=f)
		return None

	res = gen_debug_v_from_profile(args)
	if res == 3: 
		print('Warning: Please beware Probe id >= 63 cannot be used to trigger nor supports capture conditions!')
	return None

def run_top():
	args = parse_cmd_args()

	if 'EFINITY_HOME' not in os.environ:
		raise RuntimeError(f'EFINITY_HOME is not defined')
		return None

	# The caller already provides EFINITY_HOME; efx_map.exe is launched below
	# through an absolute path.  Avoid relying on PATH, which is not reliable in
	# the sandboxed wrapper used for this project.

	if not args.work_dir.is_dir():
		print(f'Create the work directory {args.work_dir}')
		args.work_dir.mkdir(parents=True)

	args.start_time = None
	if args.timeout is not None:
		args.start_time = time.monotonic()

    # do mark_debug
	if args.mark_debug is not None:
		process_mark_debug(args)

	proj_dir = args.src_dir

	syn_opts = list(map(lambda x: f'--{x}', args.map_opts))
	if not any(f'--settings_file' in s for s in args.map_opts):
		map_settings_ini = proj_dir.joinpath(f'efx_map_settings.ini')
		if map_settings_ini.is_file():
			syn_opts.extend([f'--settings_file',
				f'{map_settings_ini.resolve().as_posix()}'])

	if not proj_dir in map(lambda x: Path(x[2:]).resolve(),
			filter(lambda x: x.find('I=') == 0, args.map_opts)):
		syn_opts.extend([f'--I', f'{proj_dir.as_posix()}'])

	design_name = args.design[0]

	DEBUG_TOP_VDB = f'debug_top.post.vdb'
	debug_top_vdb_file = args.work_dir.joinpath(f'{DEBUG_TOP_VDB}')

	compile_dbg_core(device_family=args.family, device_model=args.device,
			output_vdb_file=debug_top_vdb_file,
			work_dir=args.work_dir, output_dir=args.output_dir,
			map_opts=syn_opts, timeout=calculate_timeout(args))

	profile_top_module, is_postmap, jtag_user = \
			parse_debug_profile(args.debug_profile)

	design_vdb_file = proj_dir.joinpath(f'{design_name}.vdb') if is_postmap \
			else args.output_dir.joinpath(f'{design_name}.elab.vdb')

	merged_rtl_file = args.work_dir.joinpath(f'{design_name}.dbg.map.v')
	merged_vdb_file = args.work_dir.joinpath(f'{design_name}.dbg.vdb')

	merge_vdb(device_family=args.family, device_model=args.device,
			design_vdb_file=design_vdb_file, debug_top_vdb=debug_top_vdb_file,
			top_module=[args.top_module, profile_top_module][args.top_module is None],
			profile_file=args.debug_profile.resolve().as_posix(),
			output_vdb_file=merged_vdb_file, output_rtl_file=merged_rtl_file,
			work_dir=args.work_dir, output_dir=args.output_dir,
			map_opts=syn_opts, timeout=calculate_timeout(args))

	design_peri_xml_file = proj_dir.joinpath(f'{design_name}.peri.xml')

	insert_jtag(design_name=design_name, device_model=args.device,
			peri_xml_file=design_peri_xml_file, jtag_user=jtag_user,
			output_peri_xml_file=proj_dir.joinpath(f'{design_name}.dbg.peri.xml'),
			timeout=calculate_timeout(args))

	shutil.copy(debug_top_vdb_file, args.output_dir)
	shutil.copy(merged_rtl_file, args.output_dir)
	shutil.copy(merged_vdb_file, args.output_dir)

if __name__ == '__main__':
	run_top()

