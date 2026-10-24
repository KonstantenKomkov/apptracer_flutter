#!/usr/bin/env python3
"""Bundle a compact exact-build PDB map for the Windows crash daemon."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from check_windows_native import pe_identity
from check_windows_symbols import pdb_identity, require_identity, breakpad_id


def prepare(bundle, pdb, dump_syms, executable='apptracer_desktop_example.exe'):
    if Path(executable).name != executable:
        raise ValueError('executable must be a basename')
    identity = pe_identity((bundle / executable).read_bytes())
    require_identity(identity, pdb_identity(pdb.read_bytes()))
    module_id = breakpad_id(identity)
    with tempfile.TemporaryDirectory(prefix='apptracer-pdb-') as temp:
        stage = Path(temp)
        shutil.copy2(bundle / executable, stage / executable)
        shutil.copy2(pdb, stage / pdb.name)
        output = stage / 'runner.sym'
        subprocess.run([str(dump_syms), '-o', str(output), str(stage / executable)], check=True)
        data = output.read_text(encoding='utf-8')
    if data.splitlines()[0].split() != ['MODULE', 'windows', 'x86_64', module_id, pdb.name]:
        raise ValueError('Breakpad MODULE disagrees with PE/PDB identity')
    if not any(line.startswith('FILE ') for line in data.splitlines()):
        raise ValueError('PDB must contain source lines')
    output = bundle / 'symbols' / pdb.name / module_id / (pdb.name + '.sym')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(data, encoding='utf-8')
    return {'identity': identity, 'module_id': module_id, 'output': str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--pdb', required=True, type=Path)
    parser.add_argument('--dump-syms', required=True, type=Path)
    parser.add_argument('--executable', default='apptracer_desktop_example.exe')
    args = parser.parse_args()
    print(json.dumps(prepare(args.bundle.resolve(), args.pdb.resolve(), args.dump_syms.resolve(), args.executable)))


if __name__ == '__main__':
    main()
