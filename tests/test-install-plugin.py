import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
import shutil
import subprocess
import sys
import time
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("installer", Path(__file__).parents[1] / "scripts/install-plugin.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        project = Path(__file__).parents[1]
        # Stage the actual compiled package; never install into the live shell.
        subprocess.run(["cmake", "--install", str(project / "build"), "--prefix",
                        str(project / "build/package")], check=True, capture_output=True, text=True)

    def test_installed_manifest_identifies_the_build(self):
        project = Path(__file__).parents[1]
        manifest = json.loads((project / "build/package/manifest.json").read_text())
        if shutil.which("git") and (project / ".git").exists():
            revision = subprocess.run(["git", "-C", str(project), "rev-parse", "HEAD"],
                                      capture_output=True, text=True)
            expected = revision.stdout.strip() if revision.returncode == 0 else "source"
        else:
            expected = "source"
        self.assertEqual(manifest["build"], expected)
        if expected != "source":
            self.assertRegex(manifest["build"], r"^[0-9a-f]{40}$")

    def test_manifest_stamp_tracks_revision_and_release_requirement(self):
        project = Path(__file__).parents[1]
        template = (project / "cmake/install-manifest.cmake.in").read_text()
        with tempfile.TemporaryDirectory(prefix="nookisle-manifest-") as folder:
            root = Path(folder)
            source = root / "source"
            source.mkdir()
            manifest = source / "manifest.json"
            manifest.write_bytes((project / "manifest.json").read_bytes())
            script = root / "install-manifest.cmake"
            git = shutil.which("git")

            def install(destination, executable, configured_revision="", build_type="Debug", env=None):
                content = (template.replace("@PROJECT_SOURCE_DIR@", str(source))
                                   .replace("@GIT_EXECUTABLE@", executable)
                                   .replace("@NOOKISLE_BUILD_REVISION@", configured_revision)
                                   .replace("@CMAKE_BUILD_TYPE@", build_type))
                script.write_text(content)
                run_env = os.environ.copy()
                if env:
                    run_env.update(env)
                elif "NOOKISLE_BUILD_REVISION" in run_env:
                    del run_env["NOOKISLE_BUILD_REVISION"]
                proc = subprocess.run(["cmake", "-DCMAKE_INSTALL_PREFIX=" + str(destination), "-P", str(script)],
                                      capture_output=True, text=True, env=run_env)
                return proc, (destination / "manifest.json")

            # 1. Source copy without .git in non-release mode falls back to "source"
            proc, mf_path = install(root / "archive", git or "", build_type="Debug")
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(json.loads(mf_path.read_bytes())["build"], "source")

            # 2. Release mode fails if revision is not 40-hex characters
            proc_fail, _ = install(root / "fail_rel", git or "", build_type="Release")
            self.assertNotEqual(proc_fail.returncode, 0)
            self.assertIn("requires a 40-character hex revision stamp", proc_fail.stderr)

            # 3. Explicit NOOKISLE_BUILD_REVISION stamps 40-hex in Release mode
            test_sha = "0123456789abcdef0123456789abcdef01234567"
            proc_sha, mf_sha = install(root / "sha_rel", git or "", configured_revision=test_sha, build_type="Release")
            self.assertEqual(proc_sha.returncode, 0)
            self.assertEqual(json.loads(mf_sha.read_bytes())["build"], test_sha)

            # 4. Environment variable NOOKISLE_BUILD_REVISION overrides
            env_sha = "fedcba9876543210fedcba9876543210fedcba98"
            proc_env, mf_env = install(root / "env_rel", git or "", build_type="Release", env={"NOOKISLE_BUILD_REVISION": env_sha})
            self.assertEqual(proc_env.returncode, 0)
            self.assertEqual(json.loads(mf_env.read_bytes())["build"], env_sha)

            if not git:
                return
            # 5. Git repo rev-parse HEAD produces 40 hex characters in Release mode
            subprocess.run([git, "init", "-q", str(source)], check=True)
            subprocess.run([git, "-C", str(source), "add", "manifest.json"], check=True)
            subprocess.run([git, "-C", str(source), "-c", "user.name=Build Test",
                            "-c", "user.email=build-test@example.invalid", "commit", "-qm", "Initial"], check=True)
            git_sha = subprocess.check_output([git, "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
            self.assertRegex(git_sha, r"^[0-9a-f]{40}$")

            proc_git, mf_git = install(root / "git_rel", git, build_type="Release")
            self.assertEqual(proc_git.returncode, 0)
            self.assertEqual(json.loads(mf_git.read_bytes())["build"], git_sha)

    def fixture_bindings(self, root, content=None):
        path = root / "hypr/bindings.lua"
        path.parent.mkdir(parents=True)
        path.write_bytes(content if content is not None else
                         (Path(__file__).parent / "fixtures/bindings-before.lua").read_bytes())
        return path

    def fake_hyprctl(self, root, errors="", missing_description=None, force_present=False,
                     default_left=None, wrong_mask_description=None, stale_only_description=None):
        calls = []
        path = root / "hypr/bindings.lua"

        def reply(command, **options):
            calls.append(command)
            self.assertEqual(command[0], "hyprctl")
            self.assertTrue(options["check"])
            if command[1] == "configerrors":
                output = errors
            elif command[1] == "binds":
                active = force_present or (path.exists() and installer.START_MARKER in path.read_bytes())
                bindings = []
                if active:
                    for number, (key, label, _, _) in enumerate(installer.MEDIA_BINDINGS, 6):
                        description = "Nookisle " + label
                        if stale_only_description and description != stale_only_description:
                            continue
                        binding = {"key": key.rsplit(" + ", 1)[-1],
                                   "modmask": 8 if key.startswith("ALT + ") else
                                              1 if key.startswith("SHIFT + ") else 0,
                                   "description": description, "dispatcher": "__lua", "arg": str(number)}
                        if description == missing_description:
                            del binding["description"]
                        if description == wrong_mask_description:
                            binding["modmask"] = 0
                        bindings.append(binding)
                        if label == default_left:
                            bindings.append(dict(binding, description=label, arg="omarchy"))
                output = json.dumps(bindings)
            else:
                output = ""
            return subprocess.CompletedProcess(command, 0, output)

        return calls, reply

    def test_bindings_insert_repeat_remove_preserves_fixture(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-test-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            helper = root / "omarchy/plugins" / installer.PLUGIN_ID / "libexec/nookisle-media-keys"
            calls, reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=reply):
                backup = installer.update_bindings(root, helper)
                installed = path.read_bytes()
                self.assertEqual(backup.read_bytes(), original)
                self.assertEqual(installed.count(installer.START_MARKER), 1)
                self.assertEqual(installed.count(installer.END_MARKER), 1)
                self.assertEqual(installed.count(b"hl.unbind("), 16)  # fixture plus 15 overrides
                self.assertIn(b'hl.config({ decoration = { blur = { enabled = true } } })', installed)
                self.assertIn(b'hl.layer_rule({ match = { namespace = "^nookisle$" }, blur = true, ignore_alpha = 0.5, no_anim = true })', installed)
                for direction in ("up", "down", "cycle"):
                    self.assertIn(f'"{helper} keyboard {direction}"'.encode(), installed)
                for step in ("+5%", "5%-", "100%", "1%", "+1%", "1%-"):
                    self.assertIn(f'"{helper} brightness {step}"'.encode(), installed)
                # Every key asks the island first, so the block never runs an
                # OSD-free command directly and loses the fallback readout.
                self.assertNotIn(b"--no-osd", installed)
                self.assertIn(b'o.bind("XF86AudioRaiseVolume", "Nookisle Volume up",', installed)
                self.assertIn(b'{ locked = true, repeating = true }', installed)
                self.assertIn(b'o.bind("XF86AudioMute", "Nookisle Mute",', installed)
                self.assertIsNone(installer.update_bindings(root, helper))
                self.assertEqual(path.read_bytes(), installed)
                installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([call[1:] for call in calls],
                             [["reload"], ["configerrors"], ["binds", "-j"],
                              ["reload"], ["configerrors"], ["binds", "-j"]])

    def test_bindings_no_final_newline_and_missing_file(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-edge-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root, b"-- custom\nhl.unbind('SUPER + X')")
            helper = root / "media-keys"
            _, reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=reply):
                installer.update_bindings(root, helper)
                installer.update_bindings(root, uninstall=True)
                self.assertEqual(path.read_bytes(), b"-- custom\nhl.unbind('SUPER + X')")
                installer.update_bindings(root, helper)
                with path.open("ab") as stream:
                    stream.write(b'o.bind("SUPER + B", "Later", "later-command")\n')
                installer.update_bindings(root, uninstall=True)
                self.assertEqual(path.read_bytes(),
                                 b"-- custom\nhl.unbind('SUPER + X')\n"
                                 b'o.bind("SUPER + B", "Later", "later-command")\n')
                path.unlink()
                installer.update_bindings(root, helper)
                self.assertTrue(path.exists())
                installer.update_bindings(root, uninstall=True)
                self.assertFalse(path.exists())
                installer.update_bindings(root, helper)
                with path.open("ab") as stream:
                    stream.write(b'o.bind("SUPER + X", "Custom", "custom-command")\n')
                installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), b'o.bind("SUPER + X", "Custom", "custom-command")\n')

    def test_bindings_refuse_incomplete_marker_and_restore_on_error(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-rollback-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            helper = root / "media-keys"
            path.write_bytes(original + installer.START_MARKER + b"\n")
            with self.assertRaisesRegex(ValueError, "incomplete"):
                installer.update_bindings(root, helper)
            path.write_bytes(original)
            calls, reply = self.fake_hyprctl(root, "bad option")
            with patch.object(installer.subprocess, "run", side_effect=reply):
                with self.assertRaisesRegex(ValueError, "configuration errors"):
                    installer.update_bindings(root, helper)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([call[1:] for call in calls],
                              [["reload"], ["configerrors"], ["reload"]])

    def test_bindings_write_is_durable_before_and_after_the_rename(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-durable-") as folder:
            path = Path(folder) / "bindings.lua"
            path.write_bytes(b"old\n")
            events = []
            real_fsync, real_replace = os.fsync, os.replace

            def fsync(descriptor):
                events.append(("fsync", Path(os.readlink(f"/proc/self/fd/{descriptor}")).name))
                real_fsync(descriptor)

            def replace(source, target):
                events.append(("replace", Path(target).name))
                real_replace(source, target)

            with patch.object(installer.os, "fsync", side_effect=fsync), \
                    patch.object(installer.os, "replace", side_effect=replace):
                installer.write_atomic(path, b"new\n", 0o644)
            self.assertEqual(path.read_bytes(), b"new\n")
            replaced = events.index(("replace", "bindings.lua"))
            self.assertTrue(any(kind == "fsync" and name.startswith(".nookisle-bindings-")
                                for kind, name in events[:replaced]), events)
            self.assertIn(("fsync", Path(folder).name), events[replaced + 1:])

    def test_bindings_failed_rollback_keeps_the_original_error(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-rollback-error-") as folder:
            root = Path(folder)
            self.fixture_bindings(root)
            calls, reply = self.fake_hyprctl(root, "bad option")
            real_write = installer.write_atomic
            writes = []

            def write(path, data, mode):
                writes.append(path)
                if len(writes) > 1:
                    raise OSError("disk full")
                real_write(path, data, mode)

            with patch.object(installer.subprocess, "run", side_effect=reply), \
                    patch.object(installer, "write_atomic", side_effect=write):
                with self.assertRaisesRegex(ValueError, "configuration errors") as raised:
                    installer.update_bindings(root, root / "media-keys")
            notes = "\n".join(getattr(raised.exception, "__notes__", []))
            self.assertIn("disk full", notes)
            self.assertIn(".bak.", notes)

    def test_bindings_missing_description_rolls_back(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-missing-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            calls, reply = self.fake_hyprctl(root, missing_description="Nookisle Volume up")
            with patch.object(installer.subprocess, "run", side_effect=reply):
                with self.assertRaisesRegex(ValueError, "media bindings were not loaded"):
                    installer.update_bindings(root, root / "media-keys")
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([call[1:] for call in calls],
                             [["reload"], ["configerrors"], ["binds", "-j"], ["reload"]])

    def test_bindings_wrong_modifier_mask_rolls_back_byte_identically(self):
        for label in ("Brightness maximum", "Volume up precise"):
            with self.subTest(label=label), \
                    tempfile.TemporaryDirectory(prefix="nookisle-bindings-mask-") as folder:
                root = Path(folder)
                path = self.fixture_bindings(root)
                original = path.read_bytes()
                calls, reply = self.fake_hyprctl(root, wrong_mask_description="Nookisle " + label)
                with patch.object(installer.subprocess, "run", side_effect=reply):
                    with self.assertRaisesRegex(ValueError, "media bindings were not loaded"):
                        installer.update_bindings(root, root / "media-keys")
                self.assertEqual(path.read_bytes(), original)
                self.assertEqual([call[1:] for call in calls],
                                 [["reload"], ["configerrors"], ["binds", "-j"], ["reload"]])

    def test_bindings_left_beside_omarchy_defaults_roll_back(self):
        # A plain, a Shift and an Alt key whose unbind did not match.
        for label in ("Volume up", "Brightness maximum", "Volume down precise"):
            with self.subTest(label=label), \
                    tempfile.TemporaryDirectory(prefix="nookisle-bindings-default-") as folder:
                root = Path(folder)
                path = self.fixture_bindings(root)
                original = path.read_bytes()
                calls, reply = self.fake_hyprctl(root, default_left=label)
                with patch.object(installer.subprocess, "run", side_effect=reply):
                    with self.assertRaisesRegex(ValueError, "default media bindings remain loaded"):
                        installer.update_bindings(root, root / "media-keys")
                self.assertEqual(path.read_bytes(), original)
                self.assertEqual([call[1:] for call in calls],
                                 [["reload"], ["configerrors"], ["binds", "-j"], ["reload"]])

    def test_bindings_replace_older_block_and_preserve_backup(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-upgrade-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            old_helper = root / "old/media-keys"
            new_helper = root / "new/media-keys"
            calls, reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=reply):
                installer.update_bindings(root, old_helper)
                older = path.read_bytes()
                backup = installer.update_bindings(root, new_helper)
                self.assertEqual(backup.read_bytes(), older)
                self.assertIn(str(new_helper).encode(), path.read_bytes())
                self.assertNotIn(str(old_helper).encode(), path.read_bytes())
                self.assertIsNone(installer.update_bindings(root, new_helper))
                replaced = path.read_bytes()
                _, incomplete_reply = self.fake_hyprctl(root, missing_description="Nookisle Mute")
                with patch.object(installer.subprocess, "run", side_effect=incomplete_reply):
                    with self.assertRaisesRegex(ValueError, "media bindings were not loaded"):
                        installer.update_bindings(root, root / "incomplete/media-keys")
                self.assertEqual(path.read_bytes(), replaced)
                installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([call[1:] for call in calls],
                             [["reload"], ["configerrors"], ["binds", "-j"]] * 3)

    def test_bindings_upgrade_direct_brightness_commands(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-keyboard-upgrade-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            helper = root / "media-keys"
            _, reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=reply):
                installer.update_bindings(root, helper)
                current = path.read_bytes()
                older = current
                direct = [(f"{helper} keyboard {direction}", f"omarchy-brightness-keyboard --no-osd {direction}")
                          for direction in ("up", "down", "cycle")]
                direct += [(f"{helper} brightness {step}", f"omarchy-brightness-display --no-osd {step}")
                           for step in ("+5%", "5%-", "100%", "1%", "+1%", "1%-")]
                for new_command, old_command in direct:
                    self.assertEqual(older.count(f'"{new_command}"'.encode()), 1)
                    older = older.replace(f'"{new_command}"'.encode(), f'"{old_command}"'.encode())
                path.write_bytes(older)
                backup = installer.update_bindings(root, helper)
                self.assertEqual(backup.read_bytes(), older)
                self.assertEqual(path.read_bytes(), current)
                self.assertIsNone(installer.update_bindings(root, helper))
                installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), original)

    def test_bindings_uninstall_error_restores_installed_block(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-uninstall-error-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            helper = root / "media-keys"
            _, good_reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=good_reply):
                installer.update_bindings(root, helper)
            installed = path.read_bytes()
            _, bad_reply = self.fake_hyprctl(root, "bad option")
            with patch.object(installer.subprocess, "run", side_effect=bad_reply):
                with self.assertRaisesRegex(ValueError, "configuration errors"):
                    installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), installed)

    def test_bindings_uninstall_stale_description_restores_block(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-stale-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            _, good_reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=good_reply):
                installer.update_bindings(root, root / "media-keys")
            installed = path.read_bytes()
            calls, stale_reply = self.fake_hyprctl(root, force_present=True)
            with patch.object(installer.subprocess, "run", side_effect=stale_reply):
                with self.assertRaisesRegex(ValueError, "remain loaded"):
                    installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), installed)
            self.assertEqual([call[1:] for call in calls],
                             [["reload"], ["configerrors"], ["binds", "-j"], ["reload"]])

    def test_bindings_uninstall_wrong_mask_still_restores_block(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-stale-mask-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            _, good_reply = self.fake_hyprctl(root)
            with patch.object(installer.subprocess, "run", side_effect=good_reply):
                installer.update_bindings(root, root / "media-keys")
            installed = path.read_bytes()
            label = "Nookisle Brightness maximum"
            calls, stale_reply = self.fake_hyprctl(root, force_present=True,
                wrong_mask_description=label, stale_only_description=label)
            with patch.object(installer.subprocess, "run", side_effect=stale_reply):
                with self.assertRaisesRegex(ValueError, "remain loaded"):
                    installer.update_bindings(root, uninstall=True)
            self.assertEqual(path.read_bytes(), installed)
            self.assertEqual([call[1:] for call in calls],
                             [["reload"], ["configerrors"], ["binds", "-j"], ["reload"]])

    def test_bindings_cli_requires_confirmation(self):
        package = Path(__file__).parents[1] / "build/package"
        # An alternate config root is never the live compositor's: the CLI
        # edits it without reloading or reading the running Hyprland.
        no_hyprctl = AssertionError("an alternate config root must not reach hyprctl")
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-cli-") as folder:
            root = Path(folder)
            argv = ["install-plugin.py", str(package), "--config-root", str(root), "--bindings"]
            with patch.object(sys, "argv", argv), patch("builtins.input", return_value="n"):
                installer.main()
            self.assertFalse((root / "hypr/bindings.lua").exists())
            with patch.object(sys, "argv", argv + ["--yes"]), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl), \
                    patch("builtins.input", side_effect=AssertionError("unexpected prompt")):
                installer.main()
            self.assertTrue((root / "hypr/bindings.lua").exists())
            with patch.object(sys, "argv", ["install-plugin.py", "--config-root", str(root), "--uninstall"]), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl):
                installer.main()
            self.assertFalse((root / "hypr/bindings.lua").exists())

    def test_bindings_cli_alternate_root_round_trip_is_byte_identical(self):
        package = Path(__file__).parents[1] / "build/package"
        no_hyprctl = AssertionError("an alternate config root must not reach hyprctl")
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-alt-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            install = ["install-plugin.py", str(package), "--config-root", str(root), "--bindings", "--yes"]
            with patch.object(sys, "argv", install), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl):
                installer.main()
            self.assertEqual(path.read_bytes().count(installer.START_MARKER), 1)
            self.assertEqual(len(list(path.parent.glob("bindings.lua.bak.*"))), 1)
            with patch.object(sys, "argv", ["install-plugin.py", "--config-root", str(root), "--uninstall"]), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl):
                installer.main()
            self.assertEqual(path.read_bytes(), original)

    def test_bindings_alternate_root_rollback_never_reloads_hyprland(self):
        # A failed edit of an alternate root restores it without touching the
        # live compositor, just as a successful one never reloads it.
        no_hyprctl = AssertionError("an alternate config root must not reach hyprctl")
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-alt-fail-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            write = installer.write_atomic
            attempts = []

            def failing_first_write(*arguments):
                attempts.append(arguments[0])
                if len(attempts) == 1:
                    raise OSError("disk full")
                return write(*arguments)

            with patch.object(installer, "write_atomic", side_effect=failing_first_write), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl):
                with self.assertRaisesRegex(OSError, "disk full"):
                    installer.update_bindings(root, root / "media-keys", reload=False)
            self.assertEqual(len(attempts), 2, "the edit failed, then the backup was restored")
            self.assertEqual(path.read_bytes(), original)
            package = Path(__file__).parents[1] / "build/package"
            argv = ["install-plugin.py", str(package), "--config-root", str(root), "--bindings", "--yes"]
            attempts.clear()
            with patch.object(sys, "argv", argv), \
                    patch.object(installer, "write_atomic", side_effect=failing_first_write), \
                    patch.object(installer.subprocess, "run", side_effect=no_hyprctl):
                with self.assertRaises(SystemExit):
                    installer.main()
            self.assertEqual(path.read_bytes(), original)

    def test_alternate_root_uninstall_bindings_rollback_never_calls_live_compositor(self):
        package = Path(__file__).parents[1] / "build/package"
        no_live_command = AssertionError("an alternate config root must not run a live command")
        with tempfile.TemporaryDirectory(prefix="nookisle-bindings-alt-remove-") as folder:
            root = Path(folder)
            path = self.fixture_bindings(root)
            original = path.read_bytes()
            install = ["install-plugin.py", str(package), "--config-root", str(root), "--bindings", "--yes"]
            remove = ["install-plugin.py", "--config-root", str(root), "--uninstall-bindings"]
            with patch.object(sys, "argv", install), \
                    patch.object(installer.subprocess, "run", side_effect=no_live_command):
                installer.main()
            installed = path.read_bytes()
            self.assertNotEqual(installed, original)
            write = installer.write_atomic
            attempts = []

            def fail_first_write(*arguments):
                attempts.append(arguments[0])
                if len(attempts) == 1:
                    raise OSError("disk full")
                return write(*arguments)

            with patch.object(sys, "argv", remove), \
                    patch.object(installer, "write_atomic", side_effect=fail_first_write), \
                    patch.object(installer.subprocess, "run", side_effect=no_live_command):
                with self.assertRaises(SystemExit):
                    installer.main()
            self.assertEqual(len(attempts), 2, "uninstall failed, then restored the backup")
            self.assertEqual(path.read_bytes(), installed)
            with patch.object(sys, "argv", remove), \
                    patch.object(installer.subprocess, "run", side_effect=no_live_command):
                installer.main()
            self.assertEqual(path.read_bytes(), original)

    MEDIA_FAKE = r"""#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$MEDIA_TEST_LOG"
case ${0##*/} in
  omarchy-shell)
    printf 'timeout %s\n' "${OMARCHY_SHELL_IPC_TIMEOUT:-unset}" >> "$MEDIA_TEST_LOG"
    case $* in
      *hudReadout*)
        if [ "$MEDIA_TEST_READOUT" = down ]; then exit 1; fi
        # A hung shell, one that even ignores the deadline's TERM.
        if [ "$MEDIA_TEST_READOUT" = hung ]; then trap '' TERM; sleep 5; fi
        if [ -n "${MEDIA_TEST_READOUT_DELAY:-}" ]; then sleep "$MEDIA_TEST_READOUT_DELAY"; fi
        echo "$MEDIA_TEST_READOUT" ;;
      *keyboardBacklightChanged*)
        if [ "${MEDIA_TEST_NOTIFY_FAIL:-0}" = 1 ]; then exit 1; fi ;;
    esac ;;
  omarchy-audio-output-sink) echo alsa_output.test ;;
  omarchy-audio-output-volume)
    if [ "${MEDIA_TEST_WATCH_OWNER:-0}" = 1 ]; then
      sleep 0.04
      read -r kind token owner expiry < "$XDG_RUNTIME_DIR/nookisle/key-readout.volume"
      printf 'level-owner %s\n' "$owner" >> "$MEDIA_TEST_LOG"
    fi ;;
  pactl) if [ "$1" = get-sink-volume ]; then echo "Volume: front-left: 65536 / $MEDIA_TEST_VOLUME% / 0.00 dB"; fi ;;
  date) echo "$MEDIA_TEST_NOW" ;;
  wpctl) if [ "$1" = get-volume ]; then echo "Volume: 0.42 $MEDIA_TEST_MIC"; fi ;;
  omarchy-hyprland-monitor-focused) echo "$MEDIA_TEST_MONITOR" ;;
  omarchy-hyprland-monitor-focused-apple) [ "$MEDIA_TEST_APPLE" = 1 ] ;;
  omarchy-hw-display)
    if [ -z "$MEDIA_TEST_BACKLIGHT" ]; then exit 1; fi
    echo "$MEDIA_TEST_BACKLIGHT" ;;
  omarchy-osd) exit 99 ;;
esac
"""
    MEDIA_COMMANDS = ("omarchy-shell", "omarchy-audio-output-sink", "pactl", "wpctl", "date",
                      "omarchy-brightness-keyboard-mute", "omarchy-osd", "omarchy-brightness-keyboard",
                      "omarchy-brightness-display", "omarchy-audio-output-volume", "omarchy-audio-input-mute",
                      "omarchy-hyprland-monitor-focused", "omarchy-hyprland-monitor-focused-apple",
                      "omarchy-hw-display")

    def media_keys(self, root, **values):
        """The packaged helper, with every command it runs faked and logged."""
        for name in self.MEDIA_COMMANDS:
            command = root / name
            command.write_text(self.MEDIA_FAKE)
            command.chmod(0o755)
        log = root / "calls"
        env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                   XDG_RUNTIME_DIR=str(root), MEDIA_TEST_LOG=str(log), MEDIA_TEST_NOW="1000",
                   MEDIA_TEST_VOLUME="50", MEDIA_TEST_MIC="", MEDIA_TEST_READOUT="ok",
                   MEDIA_TEST_MONITOR="eDP-1", MEDIA_TEST_APPLE="0", MEDIA_TEST_BACKLIGHT="intel_backlight")
        env.update(values)
        script = Path(__file__).parents[1] / "build/package/libexec/nookisle-media-keys"

        def run(*arguments, check=True):
            log.write_text("")
            result = subprocess.run([script, *arguments], env=env, capture_output=True, text=True)
            if check:
                self.assertEqual(result.returncode, 0, result.stderr)
            return result.returncode, log.read_text().splitlines()

        return env, run

    def test_media_keys_script_clamps_and_syncs_mic_led_without_osd(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-media-script-") as folder:
            root = Path(folder)
            env, run = self.media_keys(root, MEDIA_TEST_VOLUME="98", MEDIA_TEST_MIC="MUTED")
            entries = []
            entries += run("volume", "raise")[1]
            entries += run("volume", "+1")[1]
            entries += run("volume", "mute-toggle")[1]
            env["MEDIA_TEST_NOW"] = "1200"
            entries += run("volume", "mute-toggle")[1]
            env["MEDIA_TEST_NOW"] = "1250"
            entries += run("volume", "mute-toggle")[1]
            entries += run("mic-toggle")[1]
            env["MEDIA_TEST_VOLUME"] = "2"
            env["MEDIA_TEST_MIC"] = ""
            entries += run("volume", "lower")[1]
            entries += run("volume", "-1")[1]
            entries += run("mic-toggle")[1]
            self.assertIn("pactl set-sink-volume alsa_output.test 100%", entries)
            self.assertIn("pactl set-sink-volume alsa_output.test 99%", entries)
            self.assertIn("pactl set-sink-volume alsa_output.test 0%", entries)
            self.assertIn("pactl set-sink-volume alsa_output.test 1%", entries)
            self.assertIn("pactl set-sink-mute alsa_output.test 0", entries)
            self.assertIn("pactl set-sink-mute alsa_output.test toggle", entries)
            self.assertEqual(entries.count("pactl set-sink-mute alsa_output.test toggle"), 2)
            self.assertEqual((root / "omarchy-audio-output-volume-mute-toggle.last").read_text(), "1250\n")
            self.assertIn("omarchy-brightness-keyboard-mute on", entries)
            self.assertIn("omarchy-brightness-keyboard-mute off", entries)
            self.assertIn("omarchy-shell nookisle hudReadout volume default", entries)
            self.assertIn("omarchy-shell nookisle hudReadout mic default", entries)
            # A timestamp file holding anything but digits counts as no
            # earlier press; it is never evaluated as shell arithmetic.
            marker = root / "evaluated"
            (root / "omarchy-audio-output-volume-mute-toggle.last").write_text(f"a[$(touch {marker})]\n")
            env["MEDIA_TEST_NOW"] = "1260"
            _, calls = run("volume", "mute-toggle")
            self.assertFalse(marker.exists(), "the timestamp is not evaluated as code")
            self.assertIn("pactl set-sink-mute alsa_output.test toggle", calls)
            # The island shows these readouts, so Omarchy's never appears.
            self.assertFalse(any(line.startswith(("omarchy-osd", "omarchy-audio-output-volume",
                                                   "omarchy-audio-input-mute")) for line in entries))

    def test_media_keys_keyboard_notifies_after_brightness_even_if_ipc_fails(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-keyboard-script-") as folder:
            env, run = self.media_keys(Path(folder))
            for direction in ("up", "down", "cycle"):
                # Best effort and short: -q never fails the keypress, and a
                # hung shell holds a repeating key's helper for at most a second.
                self.assertEqual(run("keyboard", direction)[1], [
                    "omarchy-shell nookisle hudReadout keyboard default", "timeout 2s",
                    f"omarchy-brightness-keyboard --no-osd {direction}",
                    "omarchy-shell -q nookisle keyboardBacklightChanged", "timeout 1s"])
            env["MEDIA_TEST_NOTIFY_FAIL"] = "1"
            self.assertEqual(run("keyboard", "up")[1], [
                "omarchy-shell nookisle hudReadout keyboard default", "timeout 2s",
                "omarchy-brightness-keyboard --no-osd up",
                "omarchy-shell -q nookisle keyboardBacklightChanged", "timeout 1s"])

    def test_media_keys_fall_back_to_omarchy_when_the_island_shows_no_readout(self):
        # "unavailable" covers hud off, a hidden island and an
        # unwatched device; "down" is a disabled plugin or a stopped or hung
        # shell. Either way Omarchy's own command acts and shows one OSD, and
        # nothing OSD-free runs beside it.
        keys = [(("volume", "raise"), "omarchy-audio-output-volume raise"),
                (("volume", "-1"), "omarchy-audio-output-volume -1"),
                (("volume", "mute-toggle"), "omarchy-audio-output-volume mute-toggle"),
                (("mic-toggle",), "omarchy-audio-input-mute "),
                (("keyboard", "cycle"), "omarchy-brightness-keyboard cycle"),
                (("brightness", "+5%"), "omarchy-brightness-display +5%"),
                (("brightness", "1%-"), "omarchy-brightness-display 1%-")]
        for answer in ("unavailable", "down", ""):
            with self.subTest(answer=answer), \
                    tempfile.TemporaryDirectory(prefix="nookisle-media-fallback-") as folder:
                _, run = self.media_keys(Path(folder), MEDIA_TEST_READOUT=answer)
                for arguments, omarchy in keys:
                    calls = run(*arguments)[1]
                    self.assertEqual(calls[-1], omarchy, arguments)
                    actions = [line for line in calls if not line.startswith(
                        ("omarchy-shell nookisle hudReadout", "timeout ", "omarchy-hyprland-monitor-focused",
                         "omarchy-hw-display"))]
                    self.assertEqual(actions, [omarchy], arguments)

    def island_readout_allowed(self, marker, kind):
        # Run the very parser Panel uses, against the record the script wrote.
        source = Path(__file__).parents[1] / "qml/ReadoutOwner.js"
        js = ("const fs=require('fs'),vm=require('vm');"
               "const code=fs.readFileSync(process.argv[1],'utf8').replace(/^\\.pragma library\\s*/, '');"
               "const context={};vm.runInNewContext(code,context);"
               "process.stdout.write(String(context.allows(fs.readFileSync(process.argv[2],'utf8'),"
               "process.argv[3],Date.now())));")
        result = subprocess.run(["node", "-e", js, str(source), str(marker), kind],
                                check=True, capture_output=True, text=True)
        return result.stdout == "true"

    def test_media_keys_bound_a_hung_shell_and_fall_back_to_omarchy(self):
        keys = [(("volume", "raise"), "omarchy-audio-output-volume raise", "volume"),
                (("mic-toggle",), "omarchy-audio-input-mute ", "mic"),
                (("keyboard", "up"), "omarchy-brightness-keyboard up", "keyboard"),
                (("brightness", "+5%"), "omarchy-brightness-display +5%", "brightness")]
        with tempfile.TemporaryDirectory(prefix="nookisle-media-hung-") as folder:
            root = Path(folder)
            _, run = self.media_keys(root, MEDIA_TEST_READOUT="hung")
            for arguments, action, kind in keys:
                started = time.monotonic()
                calls = run(*arguments)[1]
                self.assertEqual(calls[-1], action, arguments)
                self.assertFalse(self.island_readout_allowed(root / "nookisle" / f"key-readout.{kind}", kind))
                elapsed = time.monotonic() - started
                self.assertLess(elapsed, 0.6, arguments)

    def test_media_keys_readout_owner_handles_prompt_and_late_answers(self):
        for answer, delay, expected_action, island_allowed in (
                ("ok", "", "pactl set-sink-volume alsa_output.test 55%", True),
                ("ok", "0.13", "omarchy-audio-output-volume raise", False),
                ("unavailable", "0.13", "omarchy-audio-output-volume raise", False)):
            with self.subTest(answer=answer, delay=delay), \
                    tempfile.TemporaryDirectory(prefix="nookisle-media-owner-") as folder:
                root = Path(folder)
                _, run = self.media_keys(root, MEDIA_TEST_READOUT=answer,
                                         MEDIA_TEST_READOUT_DELAY=delay)
                started = time.monotonic()
                calls = run("volume", "raise")[1]
                self.assertEqual(calls[-1], expected_action)
                self.assertLess(time.monotonic() - started, 0.3)
                marker = root / "nookisle/key-readout.volume"
                self.assertTrue(marker.exists())
                island = self.island_readout_allowed(marker, "volume")
                self.assertEqual(island, island_allowed)
                omarchy = "omarchy-audio-output-volume raise" in calls
                self.assertEqual(int(island) + int(omarchy), 1,
                                 "the decision must select exactly one visible readout")

    def test_media_keys_concurrent_repeat_keeps_fallback_owner_at_each_level_change(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-media-burst-") as folder:
            root = Path(folder)
            env, _ = self.media_keys(root, MEDIA_TEST_WATCH_OWNER="1")
            script = Path(__file__).parents[1] / "build/package/libexec/nookisle-media-keys"
            log = root / "calls"
            log.write_text("")
            children = []
            for delay in ("0.13", "0.005", "0.13", "0.005", "0.13", "0.005"):
                child_env = dict(env, MEDIA_TEST_READOUT_DELAY=delay)
                children.append(subprocess.Popen([script, "volume", "raise"], env=child_env,
                                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
                time.sleep(0.033)
            for child in children:
                _, stderr = child.communicate(timeout=3)
                self.assertEqual(child.returncode, 0, stderr)
            calls = log.read_text().splitlines()
            owners = [line for line in calls if line.startswith("level-owner ")]
            self.assertGreaterEqual(len(owners), 2, "the burst must exercise overlapping fallback actions")
            self.assertEqual(owners, ["level-owner fallback"] * len(owners),
                             "each Omarchy level change must still suppress the island readout")
            self.assertLess(sum("hudReadout volume default" in line for line in calls), len(children),
                            "subsequent keys in a fallback burst should skip the query")

    def test_media_keys_without_private_runtime_go_straight_to_omarchy(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-media-no-runtime-") as folder:
            root = Path(folder)
            env, run = self.media_keys(root)
            env.pop("XDG_RUNTIME_DIR", None)
            calls = run("volume", "raise")[1]
            self.assertEqual(calls, ["omarchy-audio-output-volume raise"])
            self.assertFalse((root / "nookisle").exists())

    def test_media_keys_brightness_follows_omarchy_display_routing(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-media-brightness-") as folder:
            env, run = self.media_keys(Path(folder))
            calls = run("brightness", "+5%")[1]
            self.assertIn("omarchy-shell nookisle hudReadout brightness intel_backlight", calls)
            self.assertEqual(calls[-1], "omarchy-brightness-display --no-osd +5%")
            # The island watches another backlight: Omarchy shows this one.
            env["MEDIA_TEST_READOUT"] = "unavailable"
            self.assertEqual(run("brightness", "100%")[1][-1], "omarchy-brightness-display 100%")
            env["MEDIA_TEST_READOUT"] = "ok"
            # An external DDC display, an Apple display, or no backlight at
            # all never reaches the island's sysfs monitor, so it is not asked.
            for monitor, apple, backlight in (("DP-1", "0", "intel_backlight"), ("HDMI-A-1", "0", ""),
                                              ("eDP-1", "1", "intel_backlight"), ("", "0", "")):
                env.update(MEDIA_TEST_MONITOR=monitor, MEDIA_TEST_APPLE=apple, MEDIA_TEST_BACKLIGHT=backlight)
                calls = run("brightness", "1%")[1]
                self.assertEqual(calls[-1], "omarchy-brightness-display 1%", (monitor, apple, backlight))
                self.assertFalse(any("hudReadout" in line for line in calls), (monitor, apple, backlight))
            # An internal panel with no monitor name still uses its backlight.
            # This is a later independent key, after the fallback burst ends.
            (Path(folder) / "nookisle/key-readout.brightness").write_text(
                "brightness 1-1 fallback 0000000000000\n")
            env.update(MEDIA_TEST_MONITOR="", MEDIA_TEST_BACKLIGHT="amdgpu_bl1")
            calls = run("brightness", "5%-")[1]
            self.assertIn("omarchy-shell nookisle hudReadout brightness amdgpu_bl1", calls)
            self.assertEqual(calls[-1], "omarchy-brightness-display --no-osd 5%-")
            for arguments in (("brightness", "5"), ("brightness", "+5%;id"), ("volume", "loud"), ("keyboard", "off")):
                code, calls = run(*arguments, check=False)
                self.assertEqual((code, calls), (1, []), arguments)

    def shell_json(self, root, bar):
        path = root / "omarchy/shell.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, "bar": bar, "plugins": []}, indent=2) + "\n")
        return path

    def run_cli(self, *arguments, answers=None):
        no_host = AssertionError("an alternate config root must not reach the live host")
        prompts = patch("builtins.input", side_effect=answers) if answers is not None else \
            patch("builtins.input", side_effect=AssertionError("unexpected prompt"))
        with patch.object(sys, "argv", ["install-plugin.py", *arguments]), \
                patch.object(installer.subprocess, "run", side_effect=no_host), prompts:
            installer.main()

    # --centre makes the island the centre anchor and remembers the anchor it
    # replaced; --uninstall puts that one back, only while the island holds it.
    def test_centre_placement_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-centre-") as folder:
            root = Path(folder)
            path = self.shell_json(root, {"position": "top", "centerAnchor": "omarchy.clock",
                                          "layout": {"center": [{"id": "omarchy.clock"}]}})
            self.run_cli("--config-root", str(root), "--centre")
            config = json.loads(path.read_text())
            self.assertEqual(config["bar"]["centerAnchor"], installer.PLUGIN_ID)
            self.assertEqual(config["bar"]["layout"], {"center": [{"id": "omarchy.clock"}]}, "nothing else changes")
            record = installer.placement_record(root)
            self.assertEqual(json.loads(record.read_text()), {"previousCenterAnchor": "omarchy.clock"})
            self.assertEqual(oct(record.stat().st_mode & 0o777), "0o600")
            self.assertEqual(len(list(path.parent.glob("shell.json.bak.*"))), 1)
            self.run_cli("--config-root", str(root), "--centre")
            self.assertEqual(len(list(path.parent.glob("shell.json.bak.*"))), 1, "a second --centre changes nothing")
            self.assertEqual(json.loads(record.read_text()), {"previousCenterAnchor": "omarchy.clock"})
            self.run_cli("--config-root", str(root), "--uninstall")
            self.assertEqual(json.loads(path.read_text())["bar"]["centerAnchor"], "omarchy.clock")
            self.assertFalse(record.exists())

    def test_centre_restore_respects_later_changes_and_absence(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-centre-absent-") as folder:
            root = Path(folder)
            path = self.shell_json(root, {"position": "top"})
            self.run_cli("--config-root", str(root), "--centre")
            self.run_cli("--config-root", str(root), "--uninstall")
            self.assertNotIn("centerAnchor", json.loads(path.read_text())["bar"], "an absent anchor is absent again")
            self.run_cli("--config-root", str(root), "--centre")
            config = json.loads(path.read_text())
            config["bar"]["centerAnchor"] = "omarchy.workspaces"
            path.write_text(json.dumps(config))
            self.run_cli("--config-root", str(root), "--uninstall")
            self.assertEqual(json.loads(path.read_text())["bar"]["centerAnchor"], "omarchy.workspaces",
                             "an anchor the person changed since is left alone")
        with tempfile.TemporaryDirectory(prefix="nookisle-centre-missing-") as folder:
            with self.assertRaises(SystemExit) as exit_code:
                self.run_cli("--config-root", folder, "--centre")
            self.assertEqual(exit_code.exception.code, 1)

    def test_live_placement_and_uninstall_use_the_host(self):
        calls = []
        folder = tempfile.TemporaryDirectory(prefix="nookisle-live-")
        root = Path(folder.name)

        def host(command, **options):
            calls.append(command)
            if command[:3] == ["omarchy", "plugin", "remove"]:
                # Omarchy moves the tree to its own backup.
                target = root / "omarchy/plugins" / installer.PLUGIN_ID
                target.rename(target.with_name("." + installer.PLUGIN_ID + ".bak.20260927"))
            return subprocess.CompletedProcess(command, 0, "ok")

        with folder:
            self.shell_json(root, {"centerAnchor": "omarchy.clock"})
            (root / "omarchy/plugins" / installer.PLUGIN_ID).mkdir(parents=True)
            (root / "omarchy/plugins" / ("." + installer.PLUGIN_ID + ".bak.older")).mkdir()
            with patch.object(installer.subprocess, "run", side_effect=host):
                installer.place_centre(root, True)
                installer.uninstall(root, True)
            recorded = installer.recorded_backups(root)
            self.assertIn("omarchy/plugins/." + installer.PLUGIN_ID + ".bak.20260927", recorded)
            self.assertNotIn("omarchy/plugins/." + installer.PLUGIN_ID + ".bak.older", recorded,
                             "a backup that was there before is not claimed")
        self.assertEqual(calls, [
            ["omarchy", "bar", "move", installer.PLUGIN_ID, "--section", "center", "--index", "0"],
            ["omarchy-shell", "shell", "reloadConfig"],
            ["omarchy-shell", "shell", "reloadConfig"],
            ["omarchy", "plugin", "remove", installer.PLUGIN_ID, "--yes"]])

    # --uninstall removes the bindings block byte-identically and the plugin
    # recoverably, and --purge offers each leftover in turn.
    def test_uninstall_removes_plugin_and_bindings_then_purge_asks(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-uninstall-") as folder, \
                tempfile.TemporaryDirectory(prefix="nookisle-state-") as state:
            root = Path(folder)
            bindings = self.fixture_bindings(root)
            original = bindings.read_bytes()
            self.run_cli(str(package), "--config-root", str(root), "--bindings", "--yes")
            target = root / "omarchy/plugins" / installer.PLUGIN_ID
            self.assertTrue(target.is_dir())
            settings = root / "nookisle"
            settings.mkdir(exist_ok=True)
            (settings / "settings.json").write_text("{}")
            (Path(state) / "nookisle").mkdir()
            self.run_cli("--config-root", str(root), "--uninstall")
            self.assertEqual(bindings.read_bytes(), original)
            self.assertFalse(target.exists())
            backups = list((root / "omarchy").glob("nookisle-backup-*"))
            self.assertEqual(len(backups), 1)
            installer.validate(backups[0])
            self.assertTrue(settings.exists(), "a plain uninstall keeps settings")
            items = [description for description, _ in installer.leftovers(root, Path(state))]
            self.assertEqual(len(items), 4, items)
            self.assertTrue(items[-1].startswith("settings"), "the settings folder, with the ledger, comes last")
            # No to the plugin backup, the config backups and the shelf; yes to settings.
            self.run_cli("--config-root", str(root), "--state-root", state, "--uninstall", "--purge",
                         answers=["n", "n", "n", "y"])
            self.assertFalse((settings / "settings.json").exists())
            self.assertTrue((Path(state) / "nookisle").exists())
            self.assertTrue(backups[0].exists())
            self.assertIn(str(backups[0].relative_to(root)), installer.recorded_backups(root),
                          "backups kept on purpose stay recorded after the settings go")
            with self.assertRaises(SystemExit):
                self.run_cli("--config-root", str(root), "--purge")

    # Purge offers only the backups this installer recorded; a file or folder
    # that merely matches their names is the person's and stays.
    def test_purge_deletes_only_recorded_backups(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-purge-own-") as folder, \
                tempfile.TemporaryDirectory(prefix="nookisle-purge-state-") as state:
            root = Path(folder)
            self.fixture_bindings(root)
            self.shell_json(root, {"centerAnchor": "omarchy.clock"})
            self.run_cli(str(package), "--config-root", str(root), "--bindings", "--yes")
            self.run_cli(str(package), "--config-root", str(root))
            self.run_cli("--config-root", str(root), "--centre")
            foreign = [root / "hypr/bindings.lua.bak.unrelated", root / "omarchy/shell.json.bak.mine"]
            for path in foreign:
                path.write_text("the person's own copy")
            foreign_dir = root / "omarchy/nookisle-backup-by-hand"
            foreign_dir.mkdir()
            recorded = installer.recorded_backups(root)
            self.assertEqual(len([e for e in recorded if e.startswith("omarchy/nookisle-backup-")]), 1,
                             "the upgrade's package backup is recorded")
            self.assertEqual(len([e for e in recorded if "shell.json.bak." in e]), 1)
            self.run_cli("--config-root", str(root), "--state-root", state, "--uninstall", "--purge", "--yes")
            for path in foreign + [foreign_dir]:
                self.assertTrue(path.exists(), str(path) + " is not the installer's")
            for entry in recorded:
                self.assertFalse((root / entry).exists(), entry + " was the installer's")
            self.assertEqual(list((root / "omarchy").glob("nookisle-backup-1*")), [])
            self.assertFalse((root / "nookisle").exists())

    # With an alternate config root, purge refuses to guess the state root:
    # the live $XDG_STATE_HOME is never touched by an isolated run.
    def test_alternate_root_purge_needs_an_explicit_state_root(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-alt-purge-") as folder, \
                tempfile.TemporaryDirectory(prefix="nookisle-live-state-") as live_state:
            root = Path(folder)
            shelf = Path(live_state) / "nookisle" / "shelf.json"
            shelf.parent.mkdir()
            shelf.write_text("{}")
            (root / "nookisle").mkdir()
            with patch.dict(os.environ, {"XDG_STATE_HOME": live_state}):
                with self.assertRaises(SystemExit) as refused:
                    self.run_cli("--config-root", str(root), "--uninstall", "--purge", "--yes")
            self.assertEqual(refused.exception.code, 2)
            self.assertTrue(shelf.exists(), "the live state root is untouched")
            self.assertTrue((root / "nookisle").exists(), "nothing was purged")

    # A keyring that refuses the clear leaves the passwords stored: purge
    # says so and the removal is incomplete, never "Deleted".
    def test_purge_reports_a_failed_keyring_clear(self):
        with tempfile.TemporaryDirectory(prefix="nookisle-keyring-") as folder, \
                tempfile.TemporaryDirectory(prefix="nookisle-keyring-state-") as state:
            root = Path(folder)
            calls = []

            def keyring(code):
                def run(command, **options):
                    calls.append(command)
                    return subprocess.CompletedProcess(command, code, "", "")
                return run

            with patch.object(installer.shutil, "which", return_value="/usr/bin/secret-tool"), \
                    patch.object(installer.subprocess, "run", side_effect=keyring(1)), \
                    patch("builtins.print") as printed:
                with self.assertRaisesRegex(ValueError, "could not be deleted"):
                    installer.purge(root, Path(state), True, True)
            self.assertEqual(calls, [["secret-tool", "clear", "service", "nookisle"]])
            self.assertNotIn("Deleted the keyring's Nookisle passwords",
                             [" ".join(map(str, call.args)) for call in printed.call_args_list])
            with patch.object(installer.shutil, "which", return_value="/usr/bin/secret-tool"), \
                    patch.object(installer.subprocess, "run", side_effect=keyring(0)):
                installer.purge(root, Path(state), True, True)
            # Without secret-tool the clear cannot be tried: also incomplete.
            calls.clear()
            with patch.object(installer.shutil, "which", return_value=None), \
                    patch.object(installer.subprocess, "run", side_effect=keyring(0)):
                with self.assertRaisesRegex(ValueError, "secret-tool is not installed"):
                    installer.purge(root, Path(state), True, True)
            self.assertEqual(calls, [], "nothing is run")
            # Declined, the keyring is not touched and nothing fails.
            with patch.object(installer.shutil, "which", return_value=None), \
                    patch("builtins.input", return_value="n"):
                installer.purge(root, Path(state), True, False)
            # Through main() on the live root, the missing tool ends the
            # removal as incomplete with exit status 1.
            home = root / "home"
            (home / ".config").mkdir(parents=True)
            with patch.object(installer.Path, "home", return_value=home), \
                    patch.object(installer.shutil, "which", return_value=None), \
                    patch.object(installer.subprocess, "run", side_effect=AssertionError("no host commands")), \
                    patch.object(sys, "argv", ["install-plugin.py", "--config-root", str(home / ".config"),
                                               "--state-root", state, "--uninstall", "--purge", "--yes"]):
                with self.assertRaises(SystemExit) as incomplete:
                    installer.main()
            self.assertEqual(incomplete.exception.code, 1)
            # main() reports any ValueError from removal as "Removal
            # incomplete" with exit status 1 (see the disk-full case).

    # An upgrade records its backup before anything moves. A ledger that
    # cannot be written leaves the old package active and makes no backup;
    # a publication that fails puts the old package back, forgets the
    # backup and raises the original error.
    def test_upgrade_records_its_backup_before_publication(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-upgrade-ledger-") as folder:
            root = Path(folder)
            target, _ = installer.install(package, root, False)
            marker = target / "old-package.txt"
            marker.write_text("the old package")

            def no_ledger(*arguments):
                raise OSError("ledger unwritable")

            with patch.object(installer, "write_json_atomic", side_effect=no_ledger):
                with self.assertRaisesRegex(OSError, "ledger unwritable"):
                    installer.install(package, root, False)
            self.assertEqual(marker.read_text(), "the old package", "the old package stays active")
            self.assertEqual(list((root / "omarchy").glob("nookisle-backup-*")), [])
            self.assertEqual(installer.recorded_backups(root), [])

            real_rename = Path.rename

            def failing_publication(self, destination):
                if ".nookisle-stage-" in str(self):
                    raise OSError("publication failed")
                return real_rename(self, destination)

            with patch.object(installer.Path, "rename", failing_publication):
                with self.assertRaisesRegex(OSError, "publication failed"):
                    installer.install(package, root, False)
            self.assertEqual(marker.read_text(), "the old package", "the old package is put back")
            self.assertEqual(list((root / "omarchy").glob("nookisle-backup-*")), [])
            self.assertEqual(installer.recorded_backups(root), [], "a backup that was undone is forgotten")
            self.assertEqual(list((root / "omarchy").glob(".nookisle-stage-*")), [])

            _, backup = installer.install(package, root, False)
            self.assertEqual((backup / marker.name).read_text(), "the old package")
            self.assertEqual(installer.recorded_backups(root), [str(backup.relative_to(root))])

    def test_enable_waits_for_exact_async_registration(self):
        package = Path(__file__).parents[1] / "build/package"
        calls = []
        inventories = iter(['[{"id":"io.github.bavanchun.nookisle-other"}]',
                            '[{"id":"io.github.bavanchun.nookisle"}]'])

        def host_reply(command, **options):
            calls.append(command)
            self.assertGreater(options["timeout"], 0)
            if command[-1] == "listPlugins":
                return subprocess.CompletedProcess(command, 0, next(inventories))
            return subprocess.CompletedProcess(command, 0, "")

        # The real built package is installed into an isolated tree. Only the
        # external host protocol boundary is controlled to reproduce scan lag.
        with tempfile.TemporaryDirectory(prefix="nookisle-scan-test-") as folder:
            with patch.object(installer.subprocess, "run", side_effect=host_reply), \
                    patch.object(installer.time, "sleep"):
                installer.install(package, Path(folder), True)
        self.assertEqual(calls, [
            ["omarchy-shell", "shell", "rescanPlugins"],
            ["omarchy-shell", "shell", "listPlugins"],
            ["omarchy-shell", "shell", "listPlugins"],
            ["omarchy", "bar", "put", installer.PLUGIN_ID, "--section", "left",
             "--after", "omarchy.workspaces"]])

    def test_registration_timeout_preserves_package_without_enabling(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-scan-timeout-") as folder:
            with patch.object(installer.subprocess, "run", return_value=
                              subprocess.CompletedProcess([], 0, "[]")) as run, \
                    patch.object(installer.time, "monotonic", side_effect=[0, 0, 6, 6]), \
                    patch.object(installer.time, "sleep"):
                with self.assertRaisesRegex(ValueError, "registration timed out"):
                    installer.install(package, Path(folder), True)
            self.assertEqual([call.args[0][-1] for call in run.call_args_list],
                             ["rescanPlugins", "listPlugins"])
            installer.validate(Path(folder) / "omarchy/plugins" / installer.PLUGIN_ID)

    def test_package_validation_and_recoverable_upgrade(self):
        # Installation tests consume the actual built package, not a fake helper.
        package = Path(__file__).parents[1] / "build/package"
        installer.validate(package)
        with tempfile.TemporaryDirectory(prefix="nookisle-install-test-") as folder:
            config = Path(folder)
            target, backup = installer.install(package, config, False)
            self.assertIsNone(backup)
            marker = target / "user-customization.txt"
            marker.write_text("preserve this change")
            target, backup = installer.install(package, config, False)
            self.assertEqual((backup / marker.name).read_text(), "preserve this change")
            self.assertFalse((target / marker.name).exists())
            self.assertTrue((target / "libexec/nookisle-helper").is_file())

    # A target that is not a directory is refused before anything is staged,
    # and a failure after staging never leaves a package copy behind.
    def test_failed_install_leaves_no_staging(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-stage-test-") as folder:
            config = Path(folder)
            plugins = config / "omarchy/plugins"
            plugins.mkdir(parents=True)
            (plugins / installer.PLUGIN_ID).write_text("not a package")
            with self.assertRaisesRegex(ValueError, "not a directory"):
                installer.install(package, config, False)
            self.assertEqual(list((config / "omarchy").glob(".nookisle-stage-*")), [])
            self.assertEqual((plugins / installer.PLUGIN_ID).read_text(), "not a package")
            (plugins / installer.PLUGIN_ID).unlink()
            with patch.object(installer.shutil, "copytree", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    installer.install(package, config, False)
            self.assertEqual(list((config / "omarchy").glob(".nookisle-stage-*")), [])
            self.assertFalse((plugins / installer.PLUGIN_ID).exists())

    def test_symlink_target_rejected(self):
        package = Path(__file__).parents[1] / "build/package"
        with tempfile.TemporaryDirectory(prefix="nookisle-link-test-") as folder:
            config = Path(folder)
            plugins = config / "omarchy/plugins"
            plugins.mkdir(parents=True)
            (plugins / installer.PLUGIN_ID).symlink_to(package, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                installer.install(package, config, False)

    def test_missing_runtime_member_rejected(self):
        package = Path(__file__).parents[1] / "build/package"
        for name in ("components/IslandSurface.qml", "components/HomeView.qml",
                     "components/PlayerPanel.qml", "components/SettingsWindow.qml",
                     "libexec/nookisle-artwork-decoder",
                     "libexec/nookisle-media-keys", "components/BrightnessSource.qml",
                     "components/HudBar.qml", "components/HudCapsule.qml",
                     "qml/HudGeometry.js", "qml/FullscreenPolicy.js", "browser/chrome/worker.js",
                     "scripts/write-private-shelf.py"):
            with self.subTest(member=name), tempfile.TemporaryDirectory(prefix="nookisle-partial-test-") as folder:
                partial = Path(folder) / "package"
                shutil.copytree(package, partial)
                # Move one real package member aside; don't substitute a fake executable.
                (partial / name).rename(Path(folder) / "withheld-member")
                with self.assertRaisesRegex(ValueError, "missing"):
                    installer.validate(partial)


    def test_spectrum_is_optional_but_must_be_executable(self):
        package = Path(__file__).parents[1] / "build/package"
        spectrum = Path("libexec/nookisle-spectrum")
        self.assertTrue((package / spectrum).is_file(), "the release package ships the spectrum")
        with tempfile.TemporaryDirectory(prefix="nookisle-spectrum-test-") as folder:
            partial = Path(folder) / "package"
            shutil.copytree(package, partial)
            # A build without libpipewire-0.3 has no spectrum binary at all.
            (partial / spectrum).rename(Path(folder) / "withheld-member")
            installer.validate(partial)
            # A present but non-executable binary would fail only at runtime.
            (Path(folder) / "withheld-member").rename(partial / spectrum)
            (partial / spectrum).chmod(0o644)
            with self.assertRaisesRegex(ValueError, "not executable: nookisle-spectrum"):
                installer.validate(partial)

if __name__ == "__main__":
    unittest.main()
