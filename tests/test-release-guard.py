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


if __name__ == "__main__":
    unittest.main()
