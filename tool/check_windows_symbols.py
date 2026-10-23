#!/usr/bin/env python3
"""Match PE/PDB/minidumps and recover runner source frames using local symbols.

The caller supplies dump_syms and rust-minidump-stackwalk executables.
No symbol servers, plugin tokens or Tracer uploads are used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid

from check_windows_native import inspect_dump, pe_identity, span, u32


def pdb_identity(data):
    """Read the PDB 7 Info stream from the MSF block directory, without DIA."""
    if span(data, 0, 32) != b'Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0':
        raise ValueError('expected an MSF 7 PDB')
    block_size, blocks, directory_size, block_map = (u32(data, n) for n in (32, 40, 44, 52))
    if block_size not in (512, 1024, 2048, 4096) or blocks * block_size != len(data):
        raise ValueError('invalid PDB block size/count')
    if directory_size < 12 or directory_size > len(data):
        raise ValueError('invalid PDB directory size')

    def block(index):
        if index >= blocks:
            raise ValueError('PDB block index out of bounds')
        return span(data, index * block_size, block_size)

    count = (directory_size + block_size - 1) // block_size
    if count * 4 > block_size:
        raise ValueError('PDB directory block map exceeds one block')
    mapping = block(block_map)
    directory = b''.join(block(u32(mapping, n * 4)) for n in range(count))[:directory_size]
    streams = u32(directory, 0)
    if streams < 2 or streams > (len(directory) - 4) // 4:
        raise ValueError('invalid PDB stream count')
    offset = 4 + streams * 4
    for index in range(2):
        size = u32(directory, 4 + index * 4)
        count = 0 if size == 0xffffffff else (size + block_size - 1) // block_size
        indexes = span(directory, offset, count * 4)
        if index == 1:
            if size == 0xffffffff or size < 28 or size > len(data):
                raise ValueError('missing PDB Info stream')
            info = b''.join(block(u32(indexes, n * 4)) for n in range(count))[:size]
            return {'guid': str(uuid.UUID(bytes_le=span(info, 12, 16))), 'age': u32(info, 8)}
        offset += count * 4
    raise ValueError('missing PDB Info stream')


def breakpad_id(identity):
    return uuid.UUID(identity['guid']).hex.upper() + format(identity['age'], 'X')


def require_identity(expected, actual):
    if actual != expected:
        raise ValueError('PE, PDB or minidump GUID/age do not match')


def runner_frames(report, executable_name):
    thread = report.get('crash_info', {}).get('crashing_thread')
    threads = report.get('threads') or []
    if not isinstance(thread, int) or not 0 <= thread < len(threads):
        raise ValueError('stackwalk report has no crashing thread')
    frames = [frame for frame in threads[thread].get('frames', [])[:1]
              if frame.get('module') == executable_name
              and 'ApptracerNativeCrashProbe' in (frame.get('function') or '')
              and frame.get('trust') == 'context'
              and (frame.get('file') or '').replace('\\', '/').endswith('/flutter_window.cpp')
              and isinstance(frame.get('line'), int) and frame['line'] > 0]
    if not frames:
        raise ValueError('crash context has no symbolized ApptracerNativeCrashProbe source frame')
    return frames


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--pdb', required=True, type=Path)
    parser.add_argument('--dump-dir', required=True, type=Path)
    parser.add_argument('--dump-syms', required=True, type=Path)
    parser.add_argument('--stackwalk', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'scope': 'local Windows runner PDB + native minidump; no Tracer acceptance',
              'success': False, 'dumps': []}
    try:
        name = 'apptracer_desktop_example.exe'
        executable = args.app / name
        identity = pe_identity(executable.read_bytes())
        require_identity(identity, pdb_identity(args.pdb.read_bytes()))
        report['identity'] = identity
        report['inputs'] = {name: sha256(executable), args.pdb.name: sha256(args.pdb)}
        report['tools'] = {path.name: sha256(path) for path in (args.dump_syms, args.stackwalk)}
        binaries = output / 'binaries'
        binaries.mkdir()
        shutil.copy2(executable, binaries / name)
        shutil.copy2(args.pdb, binaries / args.pdb.name)
        # Adjacent PDB lookup avoids reliance on absolute paths from the build host.
        raw_symbols = output / 'runner.sym'
        subprocess.run([str(args.dump_syms.resolve()), '-o', str(raw_symbols),
                        str(binaries / name)], check=True, timeout=120)
        with raw_symbols.open(encoding='utf-8') as stream:
            module = stream.readline().strip().split(' ', 4)
        if (len(module) != 5 or module[:3] != ['MODULE', 'windows', 'x86_64']
                or module[3].upper() != breakpad_id(identity)
                or module[4].lower() != args.pdb.name.lower()):
            raise ValueError('Breakpad MODULE does not match PE/PDB')
        tree = output / 'symbol-tree'
        symbol_path = tree / module[4] / module[3] / (Path(module[4]).stem + '.sym')
        symbol_path.parent.mkdir(parents=True)
        shutil.copy2(raw_symbols, symbol_path)
        report['breakpad'] = {'module': module, 'sha256': sha256(raw_symbols)}
        dumps = sorted(args.dump_dir.glob('*.dmp'))
        if not dumps:
            raise ValueError('no native minidump to symbolize')
        for dump in dumps:
            inspected = inspect_dump(dump.read_bytes(), name)
            require_identity(identity, inspected['runner']['codeview'])
            decoded = output / (dump.stem + '-stackwalk.json')
            subprocess.run([str(args.stackwalk.resolve()), '--json', '--output-file', str(decoded),
                            str(dump.resolve()), str(tree)], check=True, timeout=120)
            frames = runner_frames(json.loads(decoded.read_text(encoding='utf-8')), name)
            report['dumps'].append({'sha256': sha256(dump), 'frames': frames})
        report['success'] = True
    except Exception as error:
        report['error'] = str(error)
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'success': report['success'], 'report': str(output / 'report.json'),
                      'error': report.get('error')}))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
