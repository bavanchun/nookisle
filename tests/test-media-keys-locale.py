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

    def _setup_media_keys_test_env(self, tmp, log_file):
        root = pathlib.Path(tmp)
        bin_dir = root / "bin"
        bin_dir.mkdir(mode=0o700, exist_ok=True)
        fakes = {
            "omarchy-audio-output-sink": "#!/bin/sh\necho fake-sink\nexit 0\n",
            "omarchy-audio-output-volume": f"#!/bin/sh\necho fallback-volume \"$@\" >> '{log_file}'\nexit 0\n",
            "omarchy-shell": "#!/bin/sh\n[ \"$1\" = nookisle ] && [ \"$2\" = hudReadout ] && echo ok\nexit 0\n",
            "pactl": f"#!/bin/sh\necho \"$@\" >> '{log_file}'\nexit 0\n",
        }
        for name, body in fakes.items():
            p = bin_dir / name
            p.write_text(body)
            p.chmod(0o700)
        return {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "LOG_FILE": str(log_file)}

    def test_mute_toggle_fallback_when_runtime_dir_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            log_file = pathlib.Path(tmp) / "pactl.log"
            env = self._setup_media_keys_test_env(tmp, log_file)
            env.pop("XDG_RUNTIME_DIR", None)
            subprocess.run([str(SCRIPT), "volume", "mute-toggle"], env=env, check=True, timeout=10)
            self.assertTrue(log_file.exists())
            self.assertIn("fallback-volume mute-toggle", log_file.read_text())

    def test_mute_toggle_debounce_skipped_when_runtime_dir_mode_not_700(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            log_file = root / "pactl.log"
            env = self._setup_media_keys_test_env(tmp, log_file)
            runtime = root / "runtime"
            runtime.mkdir(mode=0o755)
            env["XDG_RUNTIME_DIR"] = str(runtime)
            subprocess.run([str(SCRIPT), "volume", "mute-toggle"], env=env, check=True, timeout=10)
            self.assertTrue(log_file.exists())
            self.assertIn("set-sink-mute fake-sink toggle", log_file.read_text())
            self.assertFalse((runtime / "omarchy-audio-output-volume-mute-toggle.last").exists())

    def test_mute_toggle_debounces_rapid_invocations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            log_file = root / "pactl.log"
            env = self._setup_media_keys_test_env(tmp, log_file)
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            env["XDG_RUNTIME_DIR"] = str(runtime)
            subprocess.run([str(SCRIPT), "volume", "mute-toggle"], env=env, check=True, timeout=10)
            self.assertTrue(log_file.exists())
            self.assertIn("set-sink-mute fake-sink toggle", log_file.read_text())
            debounce = runtime / "omarchy-audio-output-volume-mute-toggle.last"
            self.assertTrue(debounce.exists())

            log_file.unlink()
            subprocess.run([str(SCRIPT), "volume", "mute-toggle"], env=env, check=True, timeout=10)
            self.assertFalse(log_file.exists())

    def test_mute_toggle_replaces_symlink_debounce_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            log_file = root / "pactl.log"
            env = self._setup_media_keys_test_env(tmp, log_file)
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            target = root / "target"
            target.write_text("untouched")
            symlink = runtime / "omarchy-audio-output-volume-mute-toggle.last"
            symlink.symlink_to(target)
            env["XDG_RUNTIME_DIR"] = str(runtime)
            subprocess.run([str(SCRIPT), "volume", "mute-toggle"], env=env, check=True, timeout=10)
            self.assertEqual(target.read_text(), "untouched")
            self.assertFalse(symlink.is_symlink())
            self.assertTrue(symlink.is_file())


if __name__ == "__main__":
    sys.exit(unittest.main())
