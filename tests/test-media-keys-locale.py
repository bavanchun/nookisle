#!/usr/bin/env python3
"""The media-key helper's readout record must not depend on the locale: under
a comma-decimal LANG, bash formats EPOCHREALTIME with a comma, which once
turned the record's expiry into a comma expression and its token into a value
the island rejects, so both readouts showed."""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "nookisle-media-keys"


class MediaKeysLocaleTest(unittest.TestCase):
    def test_readout_record_is_locale_independent(self):
        if not shutil.which("localedef"):
            self.skipTest("localedef is not installed")
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locales, bin_dir, runtime = root / "locales", root / "bin", root / "runtime"
            for path in (locales, bin_dir, runtime):
                path.mkdir(mode=0o700)
            built = subprocess.run(["localedef", "-i", "de_DE", "-f", "UTF-8", str(locales / "de_DE.UTF-8")],
                                   capture_output=True)
            if built.returncode not in (0, 1) or not (locales / "de_DE.UTF-8").exists():
                self.skipTest("cannot build a de_DE locale here")
            fakes = {
                "omarchy-shell": "#!/bin/sh\n[ \"$1\" = nookisle ] && [ \"$2\" = hudReadout ] && echo ok\nexit 0\n",
                "omarchy-brightness-keyboard": "#!/bin/sh\nexit 0\n",
            }
            for name, body in fakes.items():
                (bin_dir / name).write_text(body)
                (bin_dir / name).chmod(0o700)
            env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "XDG_RUNTIME_DIR": str(runtime),
                   "LOCPATH": str(locales), "LANG": "de_DE.UTF-8", "LC_ALL": "de_DE.UTF-8", "HOME": tmp}
            probe = subprocess.run(["bash", "-c", "printf %s \"$EPOCHREALTIME\""], env=env, capture_output=True, text=True)
            if "," not in probe.stdout:
                self.skipTest("the locale did not change bash's decimal point")
            subprocess.run([str(SCRIPT), "keyboard", "up"], env=env, check=True, timeout=10)
            record = (runtime / "nookisle" / "key-readout.keyboard").read_text().split()
            self.assertEqual(len(record), 4, record)
            kind, token, owner, expires = record
            self.assertEqual((kind, owner), ("keyboard", "island"))
            self.assertRegex(token, r"^[0-9]+-[0-9]+$")
            self.assertRegex(expires, r"^[0-9]{13}$")


if __name__ == "__main__":
    sys.exit(unittest.main())
