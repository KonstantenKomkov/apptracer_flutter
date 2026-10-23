#!/usr/bin/env python3
"""Windows entry point; --app is the complete runner/Release directory."""
import os
from check_macos_desktop import main

if __name__ == '__main__':
    if os.name != 'nt':
        raise SystemExit('Run this probe on Windows x64.')
    raise SystemExit(main())
