#!/usr/bin/env python3
"""Atomically publish one private shelf or settings document from standard input."""

import os
from pathlib import Path
import stat
import sys
import tempfile


MAX_BYTES = 20 * 1024 * 1024


def write(path: Path, payload: bytes) -> None:
    parent = path.parent
    info = parent.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("private file directory is not private")
    prefix = f".{path.stem}-"
    fd, temporary = tempfile.mkstemp(prefix=prefix, dir=parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    args = sys.argv[1:]
    if_missing = False
    if "--if-missing" in args:
        if_missing = True
        args.remove("--if-missing")
    if len(args) != 1:
        return 2
    path = Path(args[0])
    if if_missing and path.exists():
        return 0
    payload = sys.stdin.buffer.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        return 2
    if not payload and path.name == "settings.json":
        payload = b'{"version":1,"values":{}}\n'
    try:
        write(path, payload)
    except (OSError, ValueError) as error:
        print(f"private file save failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
