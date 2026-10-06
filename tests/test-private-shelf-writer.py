"""The shelf state file is private at its first atomic publication."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


WRITER = Path(__file__).resolve().parents[1] / "scripts" / "write-private-shelf.py"


def write(path: Path, payload: bytes) -> None:
    subprocess.run([sys.executable, str(WRITER), str(path)], input=payload, check=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        state = Path(temporary) / "nookisle"
        state.mkdir(mode=0o700)
        shelf = state / "shelf.json"
        write(shelf, b'{"version":1,"items":[]}\n')
        assert shelf.stat().st_mode & 0o777 == 0o600
        assert shelf.read_bytes() == b'{"version":1,"items":[]}\n'
        assert list(state.iterdir()) == [shelf]

        shelf.chmod(0o644)
        write(shelf, b'{"version":1,"items":[{"kind":"text","text":"private"}]}\n')
        assert shelf.stat().st_mode & 0o777 == 0o600
        assert b'"private"' in shelf.read_bytes()
        assert list(state.iterdir()) == [shelf]

        state.chmod(0o755)
        failed = subprocess.run([sys.executable, str(WRITER), str(shelf)],
                                input=b'leak', capture_output=True)
        assert failed.returncode != 0
        assert b'"private"' in shelf.read_bytes()

        # Test settings.json atomic 0600 creation with --if-missing
        settings_dir = Path(temporary) / "settings_test"
        settings_dir.mkdir(mode=0o700)
        settings = settings_dir / "settings.json"
        
        # When missing, creates 0600 atomically
        res = subprocess.run([sys.executable, str(WRITER), "--if-missing", str(settings)],
                             input=b"", check=True)
        assert res.returncode == 0
        assert settings.exists()
        assert settings.stat().st_mode & 0o777 == 0o600
        assert settings.read_bytes() == b'{"version":1,"values":{}}\n'
        assert list(settings_dir.iterdir()) == [settings]

        # When already exists, --if-missing does not overwrite
        res2 = subprocess.run([sys.executable, str(WRITER), "--if-missing", str(settings)],
                              input=b'{"version":1,"values":{"mutated":true}}\n', check=True)
        assert res2.returncode == 0
        assert settings.read_bytes() == b'{"version":1,"values":{}}\n'

        # Regular write to settings.json maintains 0600
        settings.chmod(0o644)
        write(settings, b'{"version":1,"values":{"custom":true}}\n')
        assert settings.stat().st_mode & 0o777 == 0o600
        assert b'"custom"' in settings.read_bytes()


if __name__ == "__main__":
    main()
