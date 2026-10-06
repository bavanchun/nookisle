#!/usr/bin/env python3
"""Install an explicitly built plugin; never build, download, or edit vendor files."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import time

PLUGIN_ID = "io.github.bavanchun.nookisle"
START_MARKER = b"-- >>> nookisle media keys >>>"
END_MARKER = b"-- <<< nookisle media keys <<<"

# Match the OSD-producing bindings in Omarchy's default/hypr/bindings/media.lua.
# The options retain its locked and repeating behavior. Every key goes through
# the packaged helper, which leaves the readout to the island when it will
# draw one and otherwise runs Omarchy's own command with its OSD.
MEDIA_BINDINGS = (
    ("XF86AudioRaiseVolume", "Volume up", "media volume raise", True),
    ("XF86AudioLowerVolume", "Volume down", "media volume lower", True),
    ("XF86AudioMute", "Mute", "media volume mute-toggle", False),
    ("XF86AudioMicMute", "Mute microphone", "media mic-toggle", False),
    ("XF86MonBrightnessUp", "Brightness up", "media brightness +5%", True),
    ("XF86MonBrightnessDown", "Brightness down", "media brightness 5%-", True),
    ("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "media brightness 100%", True),
    ("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "media brightness 1%", True),
    ("XF86KbdBrightnessUp", "Keyboard brightness up", "media keyboard up", True),
    ("XF86KbdBrightnessDown", "Keyboard brightness down", "media keyboard down", True),
    ("XF86KbdLightOnOff", "Keyboard backlight cycle", "media keyboard cycle", False),
    ("ALT + XF86AudioRaiseVolume", "Volume up precise", "media volume +1", True),
    ("ALT + XF86AudioLowerVolume", "Volume down precise", "media volume -1", True),
    ("ALT + XF86MonBrightnessUp", "Brightness up precise", "media brightness +1%", True),
    ("ALT + XF86MonBrightnessDown", "Brightness down precise", "media brightness 1%-", True),
)


def binding_block(helper, created, added_newline):
    helper = shlex.quote(str(helper))
    lines = [START_MARKER.decode(),
             f"-- nookisle: created-file={str(created).lower()}; added-newline={str(added_newline).lower()}",
             "-- Enables blur globally because Hyprland requires it for layer blur",
             'hl.config({ decoration = { blur = { enabled = true } } })',
             'hl.layer_rule({ match = { namespace = "^nookisle$" }, blur = true, ignore_alpha = 0.5, no_anim = true })']
    for key, _, _, _ in MEDIA_BINDINGS:
        lines.append(f"hl.unbind({json.dumps(key)})")
    for key, label, command, repeating in MEDIA_BINDINGS:
        if command.startswith("media "):
            command = helper + " " + command.removeprefix("media ")
        options = "{ locked = true, repeating = true }" if repeating else "{ locked = true }"
        lines.append(f"o.bind({json.dumps(key)}, {json.dumps('Nookisle ' + label)}, "
                     f"{json.dumps(command, ensure_ascii=False)}, {options})")
    lines.append(END_MARKER.decode())
    return ("\n".join(lines) + "\n").encode()


def expected_bindings():
    # Hyprland reports modifiers separately from the key. A matching label
    # on the wrong chord is not a loaded binding for that media key.
    return {(key.rsplit(" + ", 1)[-1],
             8 if key.startswith("ALT + ") else 1 if key.startswith("SHIFT + ") else 0,
             "Nookisle " + label)
            for key, label, _, _ in MEDIA_BINDINGS}


def default_bindings():
    # Omarchy's own descriptions for the keys the block unbinds and rebinds.
    return {(key.rsplit(" + ", 1)[-1], label) for key, label, _, _ in MEDIA_BINDINGS}


def marked_span(data):
    if not (START_MARKER in data or END_MARKER in data):
        return None
    if data.count(START_MARKER) != 1 or data.count(END_MARKER) != 1:
        raise ValueError("incomplete or duplicate Nookisle bindings markers")
    start = data.index(START_MARKER)
    end = data.index(END_MARKER)
    if end < start:
        raise ValueError("Nookisle bindings markers are out of order")
    end += len(END_MARKER)
    if data[end:end + 1] == b"\n":
        end += 1
    block_lines = data[start:end].splitlines()
    if len(block_lines) < 3 or block_lines[0] != START_MARKER or block_lines[-1] != END_MARKER:
        raise ValueError("Nookisle bindings block is malformed")
    metadata = block_lines[1]
    match = re.fullmatch(rb"-- nookisle: created-file=(true|false); added-newline=(true|false)", metadata)
    if not match:
        raise ValueError("Nookisle bindings block metadata is invalid")
    created = match[1] == b"true"
    added_newline = match[2] == b"true"
    if added_newline:
        if start == 0 or data[start - 1:start] != b"\n":
            raise ValueError("Nookisle bindings block newline is missing")
        start -= 1
    return start, end, created, added_newline


def write_atomic(path, data, mode):
    # The data reaches the disk before the rename, and the rename before this
    # returns, so a crash never leaves an empty or half-written bindings file.
    descriptor, temporary = tempfile.mkstemp(prefix=".nookisle-bindings-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def verify_bindings(uninstall):
    """Reload Hyprland and confirm exactly our media bindings are loaded."""
    subprocess.run(["hyprctl", "reload"], check=True, capture_output=True, text=True, timeout=5)
    errors = subprocess.run(["hyprctl", "configerrors"], check=True,
                            capture_output=True, text=True, timeout=5).stdout.strip()
    if errors and errors.lower() not in ("no errors", "no config errors"):
        raise ValueError("Hyprland configuration errors: " + errors)
    bindings = json.loads(subprocess.run(["hyprctl", "binds", "-j"], check=True,
                                         capture_output=True, text=True, timeout=5).stdout)
    if not isinstance(bindings, list):
        raise ValueError("invalid Hyprland bindings response")
    active = set()
    active_names = set()
    for binding in bindings:
        if isinstance(binding, dict):
            key, description, mask = binding.get("key"), binding.get("description"), binding.get("modmask")
            if isinstance(key, str) and isinstance(description, str):
                active_names.add((key, description))
                if type(mask) is int:
                    active.add((key, mask, description))
    expected = expected_bindings()
    installed = expected & active
    if uninstall and {(key, description) for key, _, description in expected} & active_names:
        raise ValueError("Nookisle media bindings remain loaded")
    if not uninstall and installed != expected:
        raise ValueError("Nookisle media bindings were not loaded")
    # An unbind that fails to match (a Shift or Alt form, say) leaves
    # Omarchy's binding beside ours, and both OSDs would show.
    if not uninstall and default_bindings() & active_names:
        raise ValueError("Omarchy's default media bindings remain loaded")


def backup_ledger(config_root):
    # Every backup this installer makes is recorded here, relative to the
    # config root, so --purge offers only those and never a look-alike file.
    return config_root / "nookisle" / "backups.json"


def recorded_backups(config_root):
    try:
        entries = json.loads(backup_ledger(config_root).read_text()).get("backups", [])
    except (OSError, ValueError, AttributeError):
        return []
    safe = []
    for entry in entries if isinstance(entries, list) else []:
        if isinstance(entry, str) and entry and not entry.startswith("/") and ".." not in Path(entry).parts:
            safe.append(entry)
    return safe


def write_ledger(config_root, entries):
    ledger = backup_ledger(config_root)
    ledger.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    write_json_atomic(ledger, {"backups": entries})


def record_backup(config_root, path):
    entry = str(Path(path).relative_to(config_root))
    entries = recorded_backups(config_root)
    if entry not in entries:
        write_ledger(config_root, entries + [entry])


def forget_backup(config_root, path):
    entry = str(Path(path).relative_to(config_root))
    entries = recorded_backups(config_root)
    if entry in entries:
        write_ledger(config_root, [e for e in entries if e != entry])


def update_bindings(config_root, helper=None, uninstall=False, reload=True):
    path = config_root / "hypr/bindings.lua"
    if path.is_symlink():
        raise ValueError("refusing to edit a linked bindings.lua")
    existed = path.exists()
    if existed and not path.is_file():
        raise ValueError("bindings.lua is not a regular file")
    if uninstall and not existed:
        return None
    original = path.read_bytes() if existed else b""
    span = marked_span(original)
    if uninstall:
        if span is None:
            return None
        start, end, created, added_newline = span
        if added_newline and end < len(original):
            start += 1  # Keep the separator before content appended later.
        updated = original[:start] + original[end:]
        if created and updated:
            created = False  # Keep content the user added after installation.
    else:
        if helper is None:
            raise ValueError("media-keys helper path is required")
        if span is not None:
            start, end, created, added_newline = span
            expected = binding_block(helper, created, added_newline)
            if original[start + int(added_newline):end] == expected:
                return None
            updated = original[:start] + (b"\n" if added_newline else b"") + expected + original[end:]
        else:
            created = not existed
            added_newline = bool(original and not original.endswith(b"\n"))
            updated = original + (b"\n" if added_newline else b"") + binding_block(helper, created, added_newline)

    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if existed else 0o644
    backup = path.with_name(path.name + ".bak." + str(time.time_ns())) if existed else None
    if backup:
        shutil.copy2(path, backup)
        record_backup(config_root, backup)
    try:
        if uninstall and created:
            path.unlink()
        else:
            write_atomic(path, updated, mode)
        if reload:
            verify_bindings(uninstall)
        else:
            # An alternate config root is not the running compositor's; its
            # reload and binds would describe the live session instead.
            print("Hyprland not reloaded: the config root is not the live one")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # The original failure is the one reported; a failed rollback is added
        # to it with the backup to restore by hand.
        try:
            if existed:
                write_atomic(path, backup.read_bytes(), mode)
                shutil.copystat(backup, path)
            elif path.exists():
                path.unlink()
        except OSError as rollback:
            error.add_note(f"Restoring {path} failed ({rollback}); the previous bindings are in "
                           f"{backup}" if backup else f"Removing {path} failed ({rollback})")
        if reload:
            try:
                subprocess.run(["hyprctl", "reload"], check=True, capture_output=True, text=True, timeout=5)
            except (OSError, subprocess.SubprocessError):
                pass
        raise
    print("Updated bindings:", path)
    if backup:
        print("Previous bindings preserved:", backup)
    return backup


def write_json_atomic(path, value, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".nookisle-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def placement_record(config_root):
    # Where --centre remembers the bar's centre anchor from before, so
    # --uninstall can put it back. Kept with the plugin's own settings.
    return config_root / "nookisle" / "placement.json"


def shell_config(config_root):
    path = config_root / "omarchy" / "shell.json"
    if path.is_symlink() or not path.is_file():
        raise ValueError("shell.json not found; enable the plugin first so the host writes its bar layout")
    config = json.loads(path.read_text())
    if not isinstance(config, dict) or not isinstance(config.get("bar", {}), dict):
        raise ValueError("shell.json has no bar object")
    return path, config


def write_shell_config(config_root, path, config):
    backup = path.with_name(path.name + ".bak." + str(time.time_ns()))
    shutil.copy2(path, backup)
    record_backup(config_root, backup)
    write_json_atomic(path, config, stat.S_IMODE(path.stat().st_mode))
    print("Previous shell config preserved:", backup)


def place_centre(config_root, live):
    """Make the island the bar's centre anchor: first in the centre section,
    and bar.centerAnchor, remembering the anchor it replaces."""
    if live:
        subprocess.run(["omarchy", "bar", "move", PLUGIN_ID, "--section", "center", "--index", "0"],
                       check=True, capture_output=True, text=True, timeout=5)
    path, config = shell_config(config_root)
    bar = config.setdefault("bar", {})
    record = placement_record(config_root)
    # A second --centre keeps the anchor recorded the first time.
    if not record.exists() and bar.get("centerAnchor") != PLUGIN_ID:
        previous = {"previousCenterAnchor": bar.get("centerAnchor")} if "centerAnchor" in bar else {"previousCenterAnchor": None, "absent": True}
        record.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_json_atomic(record, previous)
    if bar.get("centerAnchor") != PLUGIN_ID:
        bar["centerAnchor"] = PLUGIN_ID
        write_shell_config(config_root, path, config)
    if live:
        subprocess.run(["omarchy-shell", "shell", "reloadConfig"], check=False, capture_output=True, text=True, timeout=5)
    print("The island is the bar's centre anchor")


def restore_centre(config_root, live):
    """Put back the centre anchor --centre replaced, if the island still holds it."""
    record = placement_record(config_root)
    if not record.is_file():
        return False
    saved = json.loads(record.read_text())
    try:
        path, config = shell_config(config_root)
    except ValueError:
        record.unlink()
        return False
    bar = config.setdefault("bar", {})
    if bar.get("centerAnchor") == PLUGIN_ID:
        if saved.get("absent"):
            del bar["centerAnchor"]
        else:
            bar["centerAnchor"] = saved.get("previousCenterAnchor")
        write_shell_config(config_root, path, config)
        if live:
            subprocess.run(["omarchy-shell", "shell", "reloadConfig"], check=False, capture_output=True, text=True, timeout=5)
        print("Restored the bar's centre anchor")
    record.unlink()
    return True


def remove_plugin(config_root, live):
    """Remove the installed tree, recoverably: through Omarchy on the live
    root (which disables it first and keeps a backup), or by moving it to a
    timestamped backup on an alternate root."""
    target = config_root / "omarchy" / "plugins" / PLUGIN_ID
    if not target.exists() and not target.is_symlink():
        return None
    if target.is_symlink():
        raise ValueError("refusing to remove a symlink installation")
    if live:
        # Omarchy names its backup; the one that appears is recorded.
        plugins = config_root / "omarchy" / "plugins"
        before = set(plugins.glob("." + PLUGIN_ID + ".bak.*"))
        subprocess.run(["omarchy", "plugin", "remove", PLUGIN_ID, "--yes"], check=True, timeout=30)
        for backup in sorted(set(plugins.glob("." + PLUGIN_ID + ".bak.*")) - before):
            record_backup(config_root, backup)
        return target
    backup = config_root / "omarchy" / ("nookisle-backup-" + str(time.time_ns()))
    target.rename(backup)
    record_backup(config_root, backup)
    print("Removed the plugin. Backup at:", backup)
    return backup


def uninstall(config_root, live):
    # Keys first, so they fall back to Omarchy's OSD before the plugin goes.
    update_bindings(config_root, uninstall=True, reload=live)
    restore_centre(config_root, live)
    remove_plugin(config_root, live)


def leftovers(config_root, state_root):
    """What stays after --uninstall, each as (description, paths), for
    --purge to offer one by one. Backups are only those the ledger records
    and that still exist; the settings folder, which holds the ledger, is
    offered last."""
    items = []
    recorded = [config_root / entry for entry in recorded_backups(config_root)]
    recorded = [p for p in recorded if not p.is_symlink() and (p.is_dir() or p.is_file())]
    plugins = [p for p in recorded if p.is_dir()]
    if plugins:
        items.append((str(len(plugins)) + " old plugin backup(s)", plugins))
    copies = [p for p in recorded if p.is_file()]
    if copies:
        items.append((str(len(copies)) + " config backup(s) this installer took before edits", copies))
    state = state_root / "nookisle"
    if state.is_dir() and not state.is_symlink():
        items.append(("the saved shelf (" + str(state) + ")", [state]))
    settings = config_root / "nookisle"
    if settings.is_dir() and not settings.is_symlink():
        items.append(("settings (" + str(settings) + ")", [settings]))
    return items


def purge(config_root, state_root, live, assume_yes):
    """Offer each leftover in turn; nothing is removed without a yes."""
    ledger_before = recorded_backups(config_root)
    for description, paths in leftovers(config_root, state_root):
        if not assume_yes and input("Delete " + description + "? [y/N] ").strip().lower() not in ("y", "yes"):
            continue
        for path in paths:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
        print("Deleted", description)
    # Deleting the settings folder took the ledger with it; backups kept on
    # purpose stay recorded for a later purge.
    remaining = [entry for entry in ledger_before if (config_root / entry).exists()]
    if remaining and not backup_ledger(config_root).exists():
        write_ledger(config_root, remaining)
    if live:
        if assume_yes or input("Delete saved CalDAV passwords from the keyring? [y/N] ").strip().lower() in ("y", "yes"):
            # Without secret-tool the clear cannot even be tried, and a
            # refusal (a locked keyring, no Secret Service) leaves the
            # passwords stored; neither may read as done.
            if not shutil.which("secret-tool"):
                raise ValueError("secret-tool is not installed, so the keyring's Nookisle passwords could not "
                                 "be deleted; any saved CalDAV passwords are still stored")
            result = subprocess.run(["secret-tool", "clear", "service", "nookisle"],
                                    capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                raise ValueError("the keyring's Nookisle passwords could not be deleted (secret-tool exit "
                                 + str(result.returncode) + "); they are still stored")
            print("Deleted the keyring's Nookisle passwords")


def wait_for_registration(timeout=5.0):
    # rescanPlugins schedules asynchronous discovery; its return is not a
    # registration barrier. Poll only the read-only inventory, never enable.
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError("plugin registration timed out; package preserved, enable not attempted")
        result = subprocess.run(["omarchy-shell", "shell", "listPlugins"],
                                check=True, capture_output=True, text=True,
                                timeout=remaining)
        try:
            plugins = json.loads(result.stdout)
        except json.JSONDecodeError:
            raise ValueError("invalid plugin registry response; enable not attempted") from None
        if not isinstance(plugins, list):
            raise ValueError("invalid plugin registry response; enable not attempted")
        if any(isinstance(plugin, dict) and plugin.get("id") == PLUGIN_ID for plugin in plugins):
            return
        time.sleep(min(0.1, max(0, deadline - time.monotonic())))


def validate(source):
    source = source.resolve(strict=True)
    manifest = json.loads((source / "manifest.json").read_text())
    if manifest.get("id") != PLUGIN_ID or manifest.get("schemaVersion") != 1:
        raise ValueError("not a Nookisle package")
    required = ["BarWidget.qml", "Panel.qml", "Service.qml", "qml/Protocol.js", "qml/SourceState.js",
                "qml/FullscreenPolicy.js", "qml/MicState.js", "qml/HudGeometry.js", "qml/HudValues.js",
                "qml/CatchZone.js",
                "scripts/write-private-shelf.py",
                "libexec/nookisle-helper", "libexec/nookisle-artwork-decoder",
                "libexec/nookisle-artwork-fetch",
                "libexec/nookisle-native-host", "libexec/nookisle-media-keys"]
    required += ["components/" + name + ".qml" for name in (
        "Artwork", "DesignTokens", "IntentSlider", "IslandButton", "IslandContent",
        "IslandIcon", "IslandSettings", "SourcePicker", "BrightnessSource", "MicSource",
        "HudBar", "HudInline", "HudBelow", "HudCapsule")]
    required += ["browser/chrome/" + name for name in (
        "manifest.json", "adapters.js", "content-script.js", "router.js", "worker.js")]
    for name in required:
        item = source / name
        if not item.is_file() or item.is_symlink():
            raise ValueError("missing or linked package member: " + name)
    for item in source.rglob("*"):
        if item.is_symlink() or not (item.is_file() or item.is_dir()):
            raise ValueError("package contains a link or special file")
    for name in ("nookisle-helper", "nookisle-artwork-decoder", "nookisle-artwork-fetch",
                 "nookisle-native-host",
                 "nookisle-media-keys"):
        if not os.access(source / "libexec" / name, os.X_OK):
            raise ValueError("helper is not executable: " + name)
    # The spectrum capture is compiled out without libpipewire-0.3, so it is
    # optional; when it ships it must still be runnable.
    spectrum = source / "libexec/nookisle-spectrum"
    if spectrum.exists() and not (spectrum.is_file() and os.access(spectrum, os.X_OK)):
        raise ValueError("helper is not executable: nookisle-spectrum")
    return source


def install(source, config_root, enable):
    source = validate(source)
    base = config_root / "omarchy"
    plugins = base / "plugins"
    target = plugins / PLUGIN_ID
    plugins.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        raise ValueError("refusing to replace a symlink installation")
    if target.exists() and not target.is_dir():
        raise ValueError("installation target is not a directory")
    # Prepare outside the watched plugins directory; publish the complete tree.
    # The staging directory is ours alone and never outlives this call.
    staging = Path(tempfile.mkdtemp(prefix=".nookisle-stage-", dir=base))
    backup = None
    try:
        staged = staging / PLUGIN_ID
        shutil.copytree(source, staged)
        if target.exists():
            # Recorded before anything moves: a ledger that cannot be written
            # leaves the old package in place, and a backup is never made
            # that purge would not know about.
            backup = base / ("nookisle-backup-" + str(time.time_ns()))
            record_backup(config_root, backup)
            try:
                target.rename(backup)
            except OSError:
                try:
                    forget_backup(config_root, backup)
                except OSError:
                    pass
                raise
        try:
            staged.rename(target)
        except OSError:
            if backup:
                # Nothing was published, so the old package goes back in
                # place and the original error is raised.
                backup.rename(target)
                try:
                    forget_backup(config_root, backup)
                except OSError:
                    pass
                backup = None
            raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print("Installed complete package:", target)
    if backup:
        print("Previous package preserved:", backup)
    if enable:
        subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], check=True, timeout=5)
        wait_for_registration()
        subprocess.run(["omarchy", "bar", "put", PLUGIN_ID, "--section", "left",
                        "--after", "omarchy.workspaces"], check=True, timeout=5)
    return target, backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", help="complete CMake staging tree")
    parser.add_argument("--enable", action="store_true", help="enable via the existing Omarchy shell")
    parser.add_argument("--bindings", action="store_true", help="install single-readout media bindings and enable global compositor blur")
    parser.add_argument("--yes", action="store_true", help="confirm the bindings edit without a prompt")
    parser.add_argument("--centre", "--center", action="store_true",
                        help="make the island the bar's centre anchor, remembering the one it replaces")
    parser.add_argument("--uninstall", action="store_true",
                        help="remove the bindings block, restore the centre anchor and remove the plugin (recoverably)")
    parser.add_argument("--purge", action="store_true",
                        help="with --uninstall, also offer to delete settings, the saved shelf, backups and keyring passwords")
    parser.add_argument("--uninstall-bindings", action="store_true",
                        help="remove only the Nookisle bindings block")
    parser.add_argument("--state-root", type=Path,
                        help="state root for --purge; defaults to $XDG_STATE_HOME only with the live config root")
    parser.add_argument("--config-root", type=Path, default=Path.home() / ".config",
                        help="config root; alternate roots are for isolated installation tests")
    args = parser.parse_args()
    removing = args.uninstall or args.uninstall_bindings
    if removing and (args.source or args.enable or args.bindings or args.centre):
        parser.error("--uninstall and --uninstall-bindings cannot install a package, bindings or placement")
    if args.purge and not args.uninstall:
        parser.error("--purge goes with --uninstall")
    if not removing and args.source is None and not args.centre:
        parser.error("a source package is required for installation")
    if (args.bindings or args.enable) and args.source is None:
        parser.error("--bindings and --enable need the source package")
    live = args.config_root.resolve() == (Path.home() / ".config").resolve()
    if args.enable and not live:
        parser.error("--enable is only valid for the actual Omarchy config root")
    # The live state root belongs with the live config root only: an
    # isolated purge must never reach the person's saved shelf.
    if args.state_root is None and args.purge:
        if not live:
            parser.error("--purge with an alternate --config-root needs an explicit --state-root")
        args.state_root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    try:
        if args.uninstall_bindings:
            update_bindings(args.config_root, uninstall=True, reload=live)
            return
        if args.uninstall:
            uninstall(args.config_root, live)
            if args.purge:
                purge(args.config_root, args.state_root, live, args.yes)
            return
        add_bindings = args.bindings
        if add_bindings and not args.yes:
            answer = input("Add Nookisle media-key bindings and enable global compositor blur in bindings.lua? [y/N] ")
            add_bindings = answer.strip().lower() in ("y", "yes")
        if args.source is not None:
            target, _ = install(args.source, args.config_root, args.enable)
            if add_bindings:
                update_bindings(args.config_root, target / "libexec/nookisle-media-keys", reload=live)
        if args.centre:
            place_centre(args.config_root, live)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, ("Removal" if removing else "Installation") + " incomplete: " + str(error) + "\n")


if __name__ == "__main__":
    main()
