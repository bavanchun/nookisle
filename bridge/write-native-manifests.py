#!/usr/bin/env python3
"""Generate registration artifacts only; never installs into a browser profile."""
import argparse
import json
import os
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--extension-id", required=True)
parser.add_argument("--binary", required=True, type=Path)
parser.add_argument("--output-dir", required=True, type=Path)
args = parser.parse_args()
if not re.fullmatch(r"[a-p]{32}", args.extension_id):
    parser.error("extension ID must contain exactly 32 lowercase letters a-p")
if not args.binary.is_absolute() or not args.binary.is_file() or not os.access(args.binary, os.X_OK):
    parser.error("binary must be an absolute path to the installed executable")
if args.output_dir.exists():
    parser.error("output directory must not exist (existing files are never overwritten)")
args.output_dir.mkdir(mode=0o700, parents=False)
origin = f"chrome-extension://{args.extension_id}/"
artifacts = {
    "io.github.bavanchun.nookisle.json": {
        "name": "io.github.bavanchun.nookisle", "description": "Nookisle exact-document transport",
        "path": str(args.binary.resolve()), "type": "stdio", "allowed_origins": [origin],
    },
    "native-host.json": {"allowedOrigin": origin},
}
for name, content in artifacts.items():
    descriptor = os.open(args.output_dir / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as file:
        json.dump(content, file, indent=2)
        file.write("\n")
