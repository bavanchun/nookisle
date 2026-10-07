import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).parents[1]
GUARD = "scripts/check-release-version.sh"


def make_tree(root, manifest="1.0.4", cmake="1.0.4", notes=None, scripts=(GUARD,)):
    """Copy the scripts under test into a scratch tree with its own manifest and CMake file."""
    (root / "scripts").mkdir()
    for script in scripts:
        shutil.copy2(PROJECT / script, root / script)
    (root / "manifest.json").write_text(
        '{\n  "schemaVersion": 1,\n  "version": "%s",\n  "build": "source"\n}\n' % manifest)
    (root / "CMakeLists.txt").write_text(
        "cmake_minimum_required(VERSION 3.25)\nproject(nookisle VERSION %s LANGUAGES CXX)\n" % cmake)
    (root / "docs" / "releases").mkdir(parents=True)
    if notes is not None:
        (root / "docs" / "releases" / f"{manifest}.md").write_text(notes)


def run_guard(root, *args):
    return subprocess.run(["bash", str(root / GUARD), *args], capture_output=True, text=True)


def git(root, *args):
    subprocess.run(["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                    *args], check=True, capture_output=True, text=True)


WRITTEN = "## What changed\nA real note.\n"


class GuardTest(unittest.TestCase):
    def setUp(self):
        self._folder = tempfile.TemporaryDirectory(prefix="nookisle-guard-")
        self.addCleanup(self._folder.cleanup)
        self.root = Path(self._folder.name)

    def assertRejects(self, result, pattern):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stderr, pattern)

    def test_matching_tree_with_tag_and_notes_passes(self):
        make_tree(self.root, notes=WRITTEN)
        result = run_guard(self.root, "--tag", "v1.0.4")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cmake_version_mismatch_is_rejected(self):
        make_tree(self.root, cmake="1.0.3", notes=WRITTEN)
        self.assertRejects(run_guard(self.root), "CMakeLists.txt project VERSION '1.0.3'")
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.4"), "CMakeLists.txt project VERSION")

    def test_tag_that_is_not_the_manifest_version_is_rejected(self):
        make_tree(self.root, notes=WRITTEN)
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.5"), "Tag 'v1.0.5' does not match")

    def test_missing_notes_are_rejected_with_a_tag(self):
        make_tree(self.root)
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.4"), "release notes at docs/releases/1.0.4.md")

    def test_empty_notes_are_rejected_with_a_tag(self):
        make_tree(self.root, notes="")
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.4"), "release notes at docs/releases/1.0.4.md")

    def test_notes_with_a_todo_marker_are_rejected_with_a_tag(self):
        make_tree(self.root, notes="## What changed\n<!-- TODO: write this -->\n")
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.4"), "TODO marker")

    def test_unreleased_version_needs_notes_without_a_tag_argument(self):
        make_tree(self.root)
        git(self.root, "init", "-q")
        self.assertRejects(run_guard(self.root), "release notes at docs/releases/1.0.4.md")

    def test_released_version_without_notes_passes_without_a_tag_argument(self):
        make_tree(self.root, manifest="1.0.3", cmake="1.0.3")
        git(self.root, "init", "-q")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "x")
        git(self.root, "tag", "v1.0.3")
        result = run_guard(self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRejects(run_guard(self.root, "--tag", "v1.0.3"), "release notes at docs/releases/1.0.3.md")

    def test_bad_arguments_print_usage(self):
        make_tree(self.root, notes=WRITTEN)
        for args in (["--tag"], ["v1.0.4"], ["--tag", ""], ["--tag", "v1.0.4", "x"]):
            result = run_guard(self.root, *args)
            self.assertEqual(result.returncode, 2, args)
            self.assertIn("Usage", result.stderr)


BUMP = "scripts/bump-version.sh"
SKIPPED = shutil.ignore_patterns(".git", "build", "plans", "out", "stage", "__pycache__")


def current_version():
    manifest = (PROJECT / "manifest.json").read_text()
    return next(line for line in manifest.splitlines() if '"version"' in line).split('"')[3]


class BumpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._folder = tempfile.TemporaryDirectory(prefix="nookisle-bump-")
        cls.copy = Path(cls._folder.name) / "repo"
        shutil.copytree(PROJECT, cls.copy, ignore=SKIPPED)
        git(cls.copy, "init", "-q")
        git(cls.copy, "add", "-A")
        cls.old = current_version()
        cls.new = "9.8.7"
        cls.result = subprocess.run(["bash", str(cls.copy / BUMP), cls.new],
                                    capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls._folder.cleanup()

    def test_run_finishes_with_the_source_contract_green(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
        self.assertIn("source contract ok", self.result.stdout)

    def test_manifest_and_cmake_move_to_the_new_version(self):
        self.assertIn(f'"version": "{self.new}"', (self.copy / "manifest.json").read_text())
        self.assertIn(f"VERSION {self.new} LANGUAGES", (self.copy / "CMakeLists.txt").read_text())
        self.assertNotIn(self.old, (self.copy / "manifest.json").read_text())

    def test_no_stale_reference_is_left_outside_the_release_notes(self):
        files = [self.copy / "README.md", *sorted((self.copy / "docs").glob("*.md"))]
        stale = [f.name for f in files if f"v{self.old}" in f.read_text()]
        self.assertEqual(stale, [])
        self.assertTrue(any(f"v{self.new}" in f.read_text() for f in files))

    def test_release_notes_template_has_four_headings_each_marked_todo(self):
        text = (self.copy / "docs" / "releases" / f"{self.new}.md").read_text()
        headings = [line for line in text.splitlines() if line.startswith("## ")]
        self.assertEqual(headings, ["## What changed", "## Fixed", "## Known limitations",
                                    "## What was tested"])
        self.assertEqual(text.count("TODO"), 4)

    def test_the_untouched_template_is_rejected_by_the_guard(self):
        for args in ([], ["--tag", f"v{self.new}"]):
            result = subprocess.run(["bash", str(self.copy / GUARD), *args],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, args)
            self.assertIn("TODO marker", result.stderr)

    def test_written_notes_pass_the_guard(self):
        notes = self.copy / "docs" / "releases" / f"{self.new}.md"
        original = notes.read_text()
        self.addCleanup(notes.write_text, original)
        notes.write_text("## What changed\nWritten.\n")
        result = subprocess.run(["bash", str(self.copy / GUARD), "--tag", f"v{self.new}"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class BumpArgumentTest(unittest.TestCase):
    def setUp(self):
        self._folder = tempfile.TemporaryDirectory(prefix="nookisle-bump-args-")
        self.addCleanup(self._folder.cleanup)
        self.root = Path(self._folder.name)
        make_tree(self.root, manifest="1.0.3", cmake="1.0.3", scripts=(GUARD, BUMP))

    def bump(self, *args):
        return subprocess.run(["bash", str(self.root / BUMP), *args], capture_output=True, text=True)

    def test_malformed_versions_and_missing_arguments_are_rejected(self):
        for args in ([], ["1.0"], ["v1.0.4"], ["1.0.4-rc1"], ["1.0.4", "x"]):
            self.assertEqual(self.bump(*args).returncode, 2, args)

    def test_the_current_version_is_rejected(self):
        result = self.bump("1.0.3")
        self.assertEqual(result.returncode, 1)
        self.assertIn("already at 1.0.3", result.stderr)

    def test_existing_notes_are_never_overwritten(self):
        notes = self.root / "docs" / "releases" / "1.0.4.md"
        notes.write_text("hand written\n")
        result = self.bump("1.0.4")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(notes.read_text(), "hand written\n")
        self.assertIn('"version": "1.0.3"', (self.root / "manifest.json").read_text())


if __name__ == "__main__":
    unittest.main()
