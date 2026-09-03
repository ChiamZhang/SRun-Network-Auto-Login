#!/usr/bin/env python3
"""Build a self-contained executable with PyInstaller.

Run this script on the target operating system; PyInstaller cannot produce a
Windows executable while running on macOS/Linux (or vice versa).
"""
from __future__ import annotations

import shutil
import subprocess
import sys


def main() -> int:
    # if shutil.which("pyinstaller") is None:
    #     print("未找到 PyInstaller，请先运行: python -m pip install pyinstaller", file=sys.stderr)
    #     return 2
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--windowed",
        "--name",
        "SRunLogin",
        "srun_gui.py",
    ]
    return subprocess.call(command)


if __name__ == "__main__":
    raise SystemExit(main())
