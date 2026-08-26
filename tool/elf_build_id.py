#!/usr/bin/env python3
"""Prints the GNU build id of an ELF file.

Used to check that the `app.<platform>-<arch>.symbols` file produced by
`--split-debug-info` really does describe the `libapp.so` shipped in the APK.
If the two build ids differ, the release's obfuscated Dart stack traces cannot
be decoded by anything, and that is worth failing a build over.

Deliberately dependency-free and self-contained: `readelf` is not installed on
a stock macOS, and a release check should not be the thing that needs a
toolchain.
"""

from __future__ import annotations

import struct
import sys

NT_GNU_BUILD_ID = 3
PT_NOTE = 4
SHT_NOTE = 7


def _unpack(fmt: str, data: bytes, offset: int, little: bool):
    prefix = "<" if little else ">"
    size = struct.calcsize(prefix + fmt)
    return struct.unpack_from(prefix + fmt, data, offset), offset + size


def _parse_notes(data: bytes, offset: int, size: int, little: bool) -> str | None:
    end = offset + size
    while offset + 12 <= end:
        (name_size, desc_size, note_type), offset = _unpack("III", data, offset, little)
        name = data[offset:offset + name_size].rstrip(b"\x00")
        offset += (name_size + 3) & ~3
        desc = data[offset:offset + desc_size]
        offset += (desc_size + 3) & ~3
        if note_type == NT_GNU_BUILD_ID and name == b"GNU":
            return desc.hex()
    return None


def build_id(path: str) -> str | None:
    with open(path, "rb") as handle:
        data = handle.read()

    if data[:4] != b"\x7fELF":
        raise ValueError(f"{path} is not an ELF file")

    is_64 = data[4] == 2
    little = data[5] == 1

    if is_64:
        (_, _, _, _, e_phoff, e_shoff), _ = _unpack("HHIQQQ", data, 16, little)
        (_, _, e_phentsize, e_phnum, e_shentsize, e_shnum), _ = _unpack(
            "IHHHHH", data, 48, little
        )
        note_fields = "IIQQQQIIQQ"  # p_type, p_flags, p_offset, ...
    else:
        (_, _, _, _, e_phoff, e_shoff), _ = _unpack("HHIIII", data, 16, little)
        (_, _, e_phentsize, e_phnum, e_shentsize, e_shnum), _ = _unpack(
            "IHHHHH", data, 36, little
        )
        note_fields = None

    # Program headers first: a stripped shared object keeps PT_NOTE.
    for index in range(e_phnum):
        offset = e_phoff + index * e_phentsize
        if is_64:
            (p_type, _p_flags, p_offset, _p_vaddr, _p_paddr, p_filesz), _ = _unpack(
                "IIQQQQ", data, offset, little
            )
        else:
            (p_type, p_offset, _p_vaddr, _p_paddr, p_filesz), _ = _unpack(
                "IIIII", data, offset, little
            )
        if p_type == PT_NOTE:
            found = _parse_notes(data, p_offset, p_filesz, little)
            if found:
                return found

    # Fall back to section headers, which a debug companion may carry instead.
    for index in range(e_shnum):
        offset = e_shoff + index * e_shentsize
        if is_64:
            (_name, sh_type, _flags, _addr, sh_offset, sh_size), _ = _unpack(
                "IIQQQQ", data, offset, little
            )
        else:
            (_name, sh_type, _flags, _addr, sh_offset, sh_size), _ = _unpack(
                "IIIIII", data, offset, little
            )
        if sh_type == SHT_NOTE:
            found = _parse_notes(data, sh_offset, sh_size, little)
            if found:
                return found

    return None


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: elf_build_id.py <elf-file>", file=sys.stderr)
        return 2
    try:
        found = build_id(argv[1])
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    if not found:
        print(f"{argv[1]}: no GNU build id", file=sys.stderr)
        return 1
    print(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
