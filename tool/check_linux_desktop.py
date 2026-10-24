#!/usr/bin/env python3
"""Ubuntu entry point; --app is the complete release/bundle directory."""
import sys
from check_macos_desktop import main

if __name__ == '__main__':
    if sys.platform != 'linux':
        raise SystemExit('Run this probe on Ubuntu x86_64.')
    raise SystemExit(main())
