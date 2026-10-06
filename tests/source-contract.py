#!/usr/bin/env python3
"""Mechanical source-contract checks that no runtime test can express.

These guard invariants that are easy to state and easy to regress silently:
the UI language, GPU effects only behind the gpuEffects gate, the absence of
a recurring UI timer, and the presence of production
properties that only a fixture currently declares.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHIPPED = [ROOT / "BarWidget.qml", ROOT / "Panel.qml", ROOT / "Service.qml"]
SHIPPED += sorted((ROOT / "components").glob("*.qml"))
SHIPPED += sorted((ROOT / "qml").glob("*.js"))

# Vietnamese-specific letters. Restricting to plain ASCII would be wrong: the UI
# legitimately uses a middot separator.
VIETNAMESE = re.compile(
    r"[À-ÃÈ-ÊÌÍÒ-ÕÙÚÝ"
    r"à-ãè-êìíò-õùúý"
    r"ĂăĐđĨĩŨũƠơƯư"
    r"Ạ-ỹ]"
)

# Unavailable under the Qt Quick software renderer, and with no gated use.
GPU_ONLY = re.compile(r"\bShaderEffect\b|\bGaussianBlur\b|\bDropShadow\b|\bParticleSystem\b")
# GPU effects that may draw only while tokens.gpuEffects is true.
GATED_EFFECT = re.compile(r"\b(MultiEffect|RectangularShadow|ShaderEffectSource)\s*\{")

failures = []


def check_no_vietnamese():
    for path in SHIPPED:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if VIETNAMESE.search(line):
                failures.append(
                    f"{path.relative_to(ROOT)}:{number}: Vietnamese text in a shipped "
                    f"surface; the UI language is English")


def check_no_gpu_only_paths():
    for path in sorted((ROOT / "components").glob("*.qml")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if GPU_ONLY.search(line):
                failures.append(
                    f"{path.relative_to(ROOT)}:{number}: not available under the "
                    f"Qt Quick software renderer")


def enclosing_blocks(text, pos):
    """The (header, body) of every `{ }` block around pos, innermost first.

    The header is the text on the line before the opening brace; the body is
    the block's text with its nested blocks blanked out, so only its own
    properties show."""
    blocks = []
    depth = 0
    for index in range(pos - 1, -1, -1):
        char = text[index]
        if char == "}":
            depth += 1
        elif char == "{":
            if depth:
                depth -= 1
                continue
            header = text[text.rfind("\n", 0, index) + 1:index]
            end, inner = index + 1, 0
            own = []
            while end < len(text):
                if text[end] == "{":
                    inner += 1
                elif text[end] == "}":
                    if not inner:
                        break
                    inner -= 1
                elif not inner:
                    own.append(text[end])
                end += 1
            blocks.append((header, "".join(own)))
    return blocks


def gate_holds(header, body):
    gated = re.compile(r"^\s*(active|layer\.enabled)\s*:.*\bgpuEffects\b", re.M)
    if re.search(r"\bLoader\s*$", header):
        return re.search(r"^\s*active\s*:.*\bgpuEffects\b", body, re.M) is not None
    if re.search(r"\blayer\.effect\s*:", header):
        return False
    return gated.search(body) is not None and re.search(r"\blayer\.effect\s*:", body) is not None


def check_gpu_effects_gated():
    """Every GPU effect sits in a Loader whose `active` reads gpuEffects, or is
    the layer effect of an item whose `layer.enabled` reads it; the software
    renderer and offscreen tests never instantiate one."""
    for path in sorted((ROOT / "components").glob("*.qml")):
        text = path.read_text()
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r"\blayer\.enabled\s*:", line) and "gpuEffects" not in line:
                failures.append(f"{path.relative_to(ROOT)}:{number}: layer.enabled must read gpuEffects")
        for match in GATED_EFFECT.finditer(text):
            number = text.count("\n", 0, match.start()) + 1
            blocks = enclosing_blocks(text, match.start())
            # The effect's own block opens at the match; the gate is its
            # host: the Loader it is the sourceComponent of, or the item it
            # is the layer effect of.
            line = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            host = blocks[0] if blocks else None
            if host and (re.search(r"\blayer\.effect\s*:", line) and gate_holds("", host[1])
                         or re.search(r"\bsourceComponent\s*:", line) and gate_holds(host[0], host[1])):
                continue
            failures.append(
                f"{path.relative_to(ROOT)}:{number}: {match.group(1)} outside the gpuEffects gate")


def check_deadlines_ignore_wall_clock():
    """Command and snapshot deadlines run on the tick-driven deadlineClock:
    a wall-clock jump across suspend must never expire a pending command."""
    service = (ROOT / "Service.qml").read_text()
    for name in ("scheduleDeadlines", "tickDeadlines"):
        body = re.search(r"function " + name + r"\(\) \{.*?\n    \}", service, re.S)
        if not body:
            failures.append(f"Service.qml: {name}() not found")
        elif "Date.now" in body.group(0):
            failures.append(f"Service.qml: {name}() reads the wall clock")
    if not re.search(r"Protocol\.feed\([^)]*root\.deadlineClock", service):
        failures.append("Service.qml: snapshot staging must be stamped with deadlineClock")
    if not re.search(r"deadline:\s*deadlineClock \+ 4000", service):
        failures.append("Service.qml: command deadlines must be set on deadlineClock")
    if 'protocolError("command-timeout")' in service or 'protocolError("gate-ack-timeout")' in service:
        failures.append("Service.qml: a timeout must restart the helper through recoverFromStall")


def check_no_recurring_ui_timer():
    for path in sorted((ROOT / "components").glob("*.qml")):
        text = path.read_text()
        if re.search(r"repeat\s*:\s*true", text):
            failures.append(
                f"{path.relative_to(ROOT)}: a repeating Timer in the UI layer; the "
                f"Service owns the only recurring cadence")


def check_absolute_positions_removed():
    """The expanded player is laid out by bands, not by absolute Y constants.

    headerHeight/transportY/statusY encoded one vertical rhythm in three
    independently maintained literals; panelHeight() is now the single authority.
    """
    tokens = (ROOT / "components" / "DesignTokens.qml").read_text()
    for name in ("headerHeight", "transportY", "statusY"):
        if re.search(rf"property\s+int\s+{name}\b", tokens):
            failures.append(
                f"components/DesignTokens.qml: {name} is back; the expanded player "
                f"is laid out by bands, not absolute Y constants")
    content = (ROOT / "components" / "IslandContent.qml").read_text()
    for number, line in enumerate(content.splitlines(), 1):
        if re.search(r"y:.*tokens\.(headerHeight|transportY|statusY)", line):
            failures.append(
                f"components/IslandContent.qml:{number}: absolute Y arithmetic")


def check_production_properties():
    """Properties a test fixture declares must also exist in production.

    Panel.qml binds bodyFontSize and BarWidget.qml reads it. When only the
    fixture declared it, the binding had no target and the bar font silently
    fell back to its literal default while the suite stayed green.
    """
    service = (ROOT / "Service.qml").read_text()
    if not re.search(r"property\s+int\s+bodyFontSize", service):
        failures.append(
            "Service.qml: missing 'property int bodyFontSize'; Panel.qml binds it "
            "and BarWidget.qml reads it")
    for name, pattern in (("islandPointerActive", r"property\s+bool\s+islandPointerActive"),
                          ("shelfItems", r"property\s+var\s+shelfItems"),
                          ("islandShowing", r"property\s+bool\s+islandShowing"),
                          ("hudSuppressed", r"property\s+bool\s+hudSuppressed"),
                          ("shelfAdd", r"function\s+shelfAdd\s*\(")):
        if not re.search(pattern, service):
            failures.append(f"Service.qml: missing {name}; the island panel and bar widget use it")


def check_hud_readout_suppression():
    """The media-key bindings trust hudReadout to say whether the island draws
    a key's readout. Panel's HudModel drops every sample while suppressed, so
    that exact state must reach the Service, or a key would show nothing."""
    panel = (ROOT / "Panel.qml").read_text()
    if not re.search(r'property:\s*"hudSuppressed"\s*\n\s*value:\s*hudModel\.suppressed\s*\n', panel):
        failures.append("Panel.qml: must bind the coordinator's hudSuppressed to hudModel.suppressed")
    service = (ROOT / "Service.qml").read_text()
    if not re.search(r"function hudReadout\(kind, device\) \{\n[^\n]*\bhudSuppressed\b", service):
        failures.append("Service.qml: hudReadout must answer no while the HUD is suppressed")
    if not re.search(r'property:\s*"hudHeldKind"\s*\n\s*value:\s*hudModel\.held\s*\?\s*hudModel\.kind\s*:\s*""', panel):
        failures.append("Panel.qml: publish the held HUD kind to the Service")
    if not re.search(r'if \(hudHeldKind !== "" && kind !== hudHeldKind\) return false', service):
        failures.append("Service.qml: other kinds must use Omarchy while a HUD bar is held")


def check_media_key_readout_ownership():
    """The helper's owner record must gate the Panel's actual HUD model."""
    panel = (ROOT / "Panel.qml").read_text()
    hud = (ROOT / "components/HudModel.qml").read_text()
    if not re.search(r"readoutAllowed:\s*root\.keyReadoutAllowed", panel):
        failures.append("Panel.qml: media-key ownership must reach HudModel")
    if not re.search(r"ReadoutOwner\.allows\(view\.text\(\), kind, Date\.now\(\)\)", panel):
        failures.append("Panel.qml: media-key ownership must gate each source sample")
    if not re.search(r"root\.readoutAllowed\(showKind\)", hud):
        failures.append("HudModel.qml: reject a fallback-owned sample")
    volume = (ROOT / "components/VolumeSource.qml").read_text()
    if not re.search(r'onLocalChange\(samples\)\s*\{\s*hudModel\.expectLocal\("volume", samples\)', panel):
        failures.append("Panel.qml: island volume writes must exempt their own source samples")
    if not re.search(r'hudModel\.expectLocal\(kind\);\s*if \(!root\.coordinator\.setBrightnessLevel', panel):
        failures.append("Panel.qml: island HUD bar writes must exempt their own brightness samples")
    if "signal localChange(int samples)" not in volume:
        failures.append("VolumeSource.qml: publish local writes before PipeWire samples")
    if not re.search(r'readoutDir:\s*readoutRuntime\s*\?\s*readoutRuntime \+ "/nookisle"\s*:\s*""', panel):
        failures.append("Panel.qml: ownership files require a session runtime directory")


def check_service_imports():
    """The lifecycle harness instantiates Service.qml, and run-lifecycle.sh
    fails on any 'Failed to load'. A PipeWire or UPower import there would make
    the Service's loadability depend on the audio or power stack; both belong
    Panel-side (components/VolumeSource.qml, components/PowerSource.qml)."""
    service = (ROOT / "Service.qml").read_text()
    if re.search(r"^\s*import\s+Quickshell\.Services\.Pipewire", service, re.M):
        failures.append("Service.qml: must not import Quickshell.Services.Pipewire; "
                        "keep it in components/VolumeSource.qml")
    if re.search(r"^\s*import\s+Quickshell\.Services\.UPower", service, re.M):
        failures.append("Service.qml: must not import Quickshell.Services.UPower; "
                        "keep it in components/PowerSource.qml")


def check_camera_import_owner():
    """Only the disposable camera source may load QtMultimedia."""
    owner = ROOT / "components" / "CameraSource.qml"
    importer = re.compile(r"^\s*import\s+QtMultimedia\b", re.M)
    if not importer.search(owner.read_text()):
        failures.append("components/CameraSource.qml: QtMultimedia import is missing")
    for path in SHIPPED:
        if path != owner and importer.search(path.read_text()):
            failures.append(f"{path.relative_to(ROOT)}: QtMultimedia belongs only in CameraSource.qml")


def check_brightness_owner():
    """Sysfs readers live in one component; backlight events come from the
    helper's own udev monitor, never a udevadm child process."""
    service = (ROOT / "Service.qml").read_text()
    source = (ROOT / "components/BrightnessSource.qml").read_text()
    for name, text in (("Service.qml", service), ("components/BrightnessSource.qml", source)):
        if "udevadm" in text:
            failures.append(f"{name}: backlight events come from the helper's udev monitor, not a udevadm child")
    if 'send("backlightWatch"' not in service:
        failures.append("Service.qml: must ask the helper to watch the backlight while the source is active")
    monitor = (ROOT / "helper/backlight-monitor.cpp").read_text()
    # LED brightness changes emit no uevent; a leds watch would never fire.
    if '"backlight"' not in monitor or '"leds"' in monitor:
        failures.append("helper/backlight-monitor.cpp: watch the backlight subsystem only; "
                        "the keyboard level is re-read on keyboardBacklightChanged()")
    if "id: backlightBrightness" in service or "id: backlightMax" in service:
        failures.append("Service.qml still owns a backlight sysfs reader")
    if '"-d", next.device, "set"' not in source:
        failures.append("BrightnessSource.qml must route writes through brightnessctl -d")


# The camera runs only while its tile is visible in an open, settled island
# on Home, or in the onboarding camera test after an explicit press. Each link
# of those gates is pinned where it lives; only Home and the onboarding view
# host the mirror panel, whose Loader alone creates the capture source.
CAMERA_GATE = {
    "components/CameraSource.qml": [
        r"readonly property bool captureAllowed: enabled && islandOpen && onHome && tileVisible",
        r"active: root\.captureAllowed && root\.hasCamera",
        r"active: root\.captureAllowed && formatApplied\n",
    ],
    "components/CameraPanel.qml": [
        r"readonly property bool captureAllowed: enabled && islandOpen && onHome && tileVisible",
        r"active: root\.captureAllowed && root\.revealed",
    ],
    "Panel.qml": [
        r"hostVisible: panel\.visible",
    ],
    "components/HomeView.qml": [
        r"enabled: root\.mirrorShown",
        r"islandOpen: root\.islandOpen",
        r"onHome: root\.onHome",
        r"tileVisible: visible && !root\.cameraCoveredByOverlay",
    ],
    "components/IslandSurface.qml": [
        r"readonly property bool openSettled: hostVisible && expanded && !morph\.running",
        r"islandOpen: root\.openSettled",
        r'onHome: root\.view === "home"',
    ],
    # The onboarding camera test: a second host, gated on an explicit press
    # on the camera step of a visible, allowed window, withdrawn on any step
    # change or when the window is hidden or disallowed.
    "components/OnboardingView.qml": [
        r"enabled: root\.cameraTestRequested",
        r"islandOpen: root\.cameraHostAllowed",
        r'onHome: root\.step\.id === "camera"',
        r"tileVisible: visible",
        r"readonly property bool cameraHostAllowed: hostVisible\n\s*&& \(!coordinator \|\| coordinator\.windowsAllowed !== false\)",
        r"onStepChanged: cameraTestRequested = false",
        r"onCameraHostAllowedChanged: if \(!cameraHostAllowed\) cameraTestRequested = false",
    ],
    "components/OnboardingWindow.qml": [
        r"hostVisible: window\.visible",
    ],
}
CAMERA_HOSTS = {"CameraSource": ["CameraPanel.qml"], "CameraPanel": ["HomeView.qml", "OnboardingView.qml"]}


def check_camera_gate():
    """The camera is gated on visibility, and hosted only behind that gate."""
    for name, patterns in CAMERA_GATE.items():
        text = (ROOT / name).read_text()
        for pattern in patterns:
            if not re.search(pattern, text):
                failures.append(f"{name}: camera visibility gate is missing '{pattern}'")
    for component, hosts in CAMERA_HOSTS.items():
        use = re.compile(r"^\s*" + component + r"\s*\{", re.M)
        for path in SHIPPED:
            if path.name not in hosts and use.search(path.read_text()):
                failures.append(f"{path.relative_to(ROOT)}: {component} belongs only in {' or '.join(hosts)}")


# qml/Settings.js is the single list of setting keys. The eleven booleans a bar
# entry has always carried stay in the host's shell.json, in this order;
# positional so a silent reorder or drop is caught, not only an addition.
LEGACY_KEYS = ["autoShow", "reducedMotion", "highContrast", "remoteArtwork",
               "island", "hud", "visualizer", "peek", "tint", "power", "lyrics"]


def check_fixed_plugin_windows():
    """The settings and welcome windows open at one size, floating and
    centred. Hyprland floats a toplevel whose minimum and maximum sizes are
    equal, so both sizes must be pinned to the window's own size; no window
    rule is installed for them."""
    for name in ("SettingsWindow.qml", "OnboardingWindow.qml"):
        text = (ROOT / "components" / name).read_text()
        for bound in ("minimumSize", "maximumSize"):
            if f"{bound}: Qt.size(implicitWidth, implicitHeight)" not in text:
                failures.append(f"components/{name}: {bound} must equal the window's implicit size so it floats")


def check_settings_documented():
    """docs/settings.md documents every visible setting: each schema key
    without internal:true has a row there."""
    schema = (ROOT / "qml" / "Settings.js").read_text()
    start = schema.find("var SCHEMA = [")
    doc = (ROOT / "docs" / "settings.md").read_text()
    for body in re.findall(r"\{([^{}]*)\}", schema[start:schema.find("\n]", start)]):
        key = re.search(r'\bkey:\s*"(\w+)"', body)
        if key and "internal: true" not in body and f"`{key.group(1)}`" not in doc:
            failures.append(f"docs/settings.md: the visible setting {key.group(1)} has no row")


def check_camera_order_pruned():
    """An island unplugged while open never keeps the camera: Panel prunes
    the camera open order whenever the screens with an island change."""
    panel = (ROOT / "Panel.qml").read_text()
    if "onCameraScreensChanged: cameraOpenOrder = Displays.pruneCameraOrder(cameraOpenOrder, cameraScreens)" not in panel:
        failures.append("Panel.qml: the camera open order must be pruned when the screens change")


def check_battery_warning_banner():
    """Low and critical battery warnings reach the banner in the default
    banner style: Panel hands PeekModel's crossing to BatteryModel.warn."""
    panel = (ROOT / "Panel.qml").read_text()
    if not re.search(r"function onBatteryWarning\(kind, level\) \{ batteryModel\.warn\(kind, level\) \}", panel):
        failures.append("Panel.qml: PeekModel's batteryWarning must reach batteryModel.warn")


def schema_entries():
    """(key, store) pairs of qml/Settings.js in declaration order. Entries are
    flat object literals, so no brace nests inside one."""
    text = (ROOT / "qml" / "Settings.js").read_text()
    start = text.find("var SCHEMA = [")
    if start < 0:
        failures.append("qml/Settings.js: the SCHEMA array is missing")
        return []
    entries = []
    for body in re.findall(r"\{([^{}]*)\}", text[start:text.find("\n]", start)]):
        key = re.search(r'\bkey:\s*"(\w+)"', body)
        store = re.search(r'\bstore:\s*"(\w+)"', body)
        if not key or not store:
            failures.append(f"qml/Settings.js: a schema entry lacks a key or store: {body.strip()[:60]}")
            continue
        entries.append((key.group(1), store.group(1)))
    return entries


def check_setting_keys():
    entries = schema_entries()
    shell_keys = [key for key, store in entries if store == "shell"]
    if shell_keys != LEGACY_KEYS:
        failures.append(f"qml/Settings.js: the shell-store keys are {shell_keys}, expected {LEGACY_KEYS}")
    for key, store in entries:
        if store not in ("shell", "file"):
            failures.append(f"qml/Settings.js: {key} has store {store!r}; only shell and file exist")
    service = (ROOT / "Service.qml").read_text()
    if not re.search(r'settingKeys:\s*Settings\.keys\("shell"\)', service):
        failures.append('Service.qml: settingKeys must be derived as Settings.keys("shell")')
    if not re.search(r"Settings\.validateBatch\(options\)", service):
        failures.append("Service.qml: configure() must validate through Settings.validateBatch")
    # No second hand-written key list anywhere in the Service.
    for key in LEGACY_KEYS[:2]:
        if f'"{key}"' in service:
            failures.append(f'Service.qml: names the setting "{key}" as a string; derive keys from qml/Settings.js')


OPT_IN_SETTINGS = ("lyrics", "hud")


def check_lyrics_opt_in():
    """Settings that send data off the machine or duplicate desktop OSDs
    must default off (settings.x === true)."""
    service = (ROOT / "Service.qml").read_text()
    paths = [ROOT / "Service.qml", ROOT / "Panel.qml", *sorted((ROOT / "components").glob("*.qml"))]
    for key in OPT_IN_SETTINGS:
        if f"settings.{key} === true" not in service:
            failures.append(f"Service.qml: expected 'settings.{key} === true' (opt-in default)")
        for path in paths:
            if re.search(rf"\b{key}\s*!==\s*false", path.read_text()):
                failures.append(f"{path.relative_to(ROOT)}: {key} must not default on via '!== false'")


FINITE_MOTION = re.compile(r"\bFrameAnimation\b|\bSpringAnimation\b|Animation\.Infinite\b")


# Loops pinned to the gate that stops them: they loop only while shown and
# only while their content needs it.
LOOP_EXEMPT = {
    "Marquee.qml": r"readonly property bool scrolling: visible && hostVisible && overflowing",
    # The blink re-arms a single-shot timer (a repeating one is banned
    # outright) only while this gate holds.
    "IdleFace.qml": r"readonly property bool blinking: visible && hostVisible && !reducedMotion && mood === \"neutral\"",
}


# Loops gated directly on visibility: each must run only while visible. With
# LOOP_EXEMPT, these are the only infinite loops the island may run.
LOOP_EXEMPTIONS = {}


def check_finite_motion():
    """All island motion is finite and event-triggered: no perpetual driver,
    apart from the named and pinned loop exemptions, each gated on visibility."""
    for path in sorted((ROOT / "components").glob("*.qml")):
        text = path.read_text()
        if path.name in LOOP_EXEMPTIONS:
            loops = text.count("Animation.Infinite")
            gated = len(re.findall(r"^\s*running:\s*root\.visible\b", text, re.M))
            if loops == 0:
                failures.append(f"{path.relative_to(ROOT)}: listed as a loop exemption but has no loop")
            elif gated < loops:
                failures.append(f"{path.relative_to(ROOT)}: each infinite loop must run only while "
                                f"visible ('running: root.visible && ...')")
            continue
        exempt = LOOP_EXEMPT.get(path.name)
        if exempt and not re.search(exempt, text):
            failures.append(f"{path.relative_to(ROOT)}: its loop must run only while visible and needed")
        for number, line in enumerate(text.splitlines(), 1):
            if exempt and re.search(r"\bAnimation\.Infinite\b", line) and not re.search(r"\bFrameAnimation\b|\bSpringAnimation\b", line):
                continue
            if FINITE_MOTION.search(line):
                failures.append(
                    f"{path.relative_to(ROOT)}:{number}: FrameAnimation, SpringAnimation "
                    f"and Animation.Infinite are banned; motion must be finite")


def check_status_redaction():
    """status() may report how many files are shelved, never which, and how
    many apps capture each device, never which."""
    service = (ROOT / "Service.qml").read_text()
    match = re.search(r"function\s+status\(\)[^{]*\{(.*?)\n        \}", service, re.S)
    if not match:
        failures.append("Service.qml: status() not found")
        return
    for use in re.findall(r"shelf(?:Items|Entries)(\.\w+)?", match.group(1)):
        if use != ".length":
            failures.append("Service.qml: status() exposes shelf contents; only the shelf's length is allowed")
    if re.search(r"cameraHolders|privacyLoader|\.mic\b|\.camera\b|\.screen\b", match.group(1)):
        failures.append("Service.qml: status() exposes capturing apps; only privacyCounts is allowed")
    report = re.search(r"function reportActivity\([^)]*\)\s*\{(.*?)\n    \}", service, re.S)
    if not report or "privacyCounts = {" not in report.group(1) or ".length" not in report.group(1):
        failures.append("Service.qml: reportActivity must keep only counts of the capturing apps")


def check_catch_zone_tradeoff_documented():
    """The catch zone takes the host bar's pointer input over the empty
    centre (a Wayland input region cannot let clicks through while catching
    drags). The user-facing docs and the setting's help must keep saying so,
    with the way to turn it off."""
    features = (ROOT / "docs" / "features.md").read_text()
    for phrase in ("centre gestures do not work inside the zone", "expandedDragDetection", "dragCatchWidth"):
        if phrase not in features:
            failures.append(f"docs/features.md: the catch zone section must document the lost bar input ('{phrase}')")
    settings = (ROOT / "qml" / "Settings.js").read_text()
    entry = re.search(r'\{\s*key:\s*"expandedDragDetection".*?\}', settings, re.S)
    if not entry or "bar's own clicks" not in entry.group(0):
        failures.append("qml/Settings.js: expandedDragDetection's help must say the zone takes the bar's own clicks")


def check_calendar_url_credentials():
    """A calendar source URL never carries a user name or password: the
    central settings check, the editor's source builder and every helper
    path that could hand a URL to secret-tool refuse it, and the helper's
    calendar code never logs."""
    settings = (ROOT / "qml" / "Settings.js").read_text()
    calendar = (ROOT / "qml" / "Calendar.js").read_text()
    check_source = re.search(r"function checkSource\(source\) \{.*?\n\}", settings, re.S)
    if not check_source or "hasUserinfo(source.url)" not in check_source.group(0):
        failures.append("qml/Settings.js: checkSource must refuse a URL with userinfo")
    make_source = re.search(r"function makeSource\(.*?\n\}", calendar, re.S)
    if not make_source or "hasUserinfo(url)" not in make_source.group(0):
        failures.append("qml/Calendar.js: makeSource must refuse a URL with userinfo")
    for name in ("calendar-sources.cpp", "calendar-service.cpp", "calendar-parser.cpp"):
        path = ROOT / "helper" / name
        if not path.exists():
            continue
        text = path.read_text()
        if re.search(r"\bq(Debug|Info|Warning|Critical)\b|\bfprintf\b|\bstd::c(err|out)\b|\bqPrintable\b", text):
            failures.append(f"helper/{name}: calendar code must not log; a URL may carry a secret")
    helper = (ROOT / "helper" / "calendar-sources.cpp").read_text()
    for function in ("void Sources::lookupPassword", "void Sources::credential", "void Sources::configure"):
        body = re.search(re.escape(function) + r"\(.*?\n\}", helper, re.S)
        if not body or "hasUserInfo(" not in body.group(0):
            failures.append(f"helper/calendar-sources.cpp: {function.split('::')[1]} must refuse a URL with userinfo")


def check_calendar_boundary():
    helper = (ROOT / "helper" / "calendar-sources.cpp").read_text()
    service = (ROOT / "Service.qml").read_text()
    source = (ROOT / "components" / "CalendarSource.qml").read_text()
    # The password is secret-tool's standard input, never one of its arguments.
    if ("process->write(input)" not in helper or not re.search(r"secretTool\(arguments,\s*password,", helper)
            or re.search(r"<<\s*password\b", helper) or "secret-tool" not in helper):
        failures.append("helper/calendar-sources.cpp: credential store must write the password to secret-tool stdin")
    if '"clear"' in re.search(r"void Sources::configure\(.*?\n\}", helper, re.S).group(0):
        failures.append("helper/calendar-sources.cpp: reconfiguring sources must never clear a stored password")
    for marker in ("setPeerVerifyName", "NoProxy", "private-address", "redirect-refused", "abortHostLookup", "calendarTooLarge"):
        if marker not in helper:
            failures.append(f"helper/calendar-sources.cpp: missing calendar network boundary {marker}")
    if not re.search(r"active:\s*root.showCalendar\s*&&\s*root.calendarSupported\s*&&\s*root.island\s*&&\s*root.uiAllowed", service):
        failures.append("Service.qml: CalendarSource loader must require island mode, admission and opt-in")
    for verb in ("calendarConfigure", "calendarWindow", "calendarSetCompleted", "calendarCredential", "calendarTest"):
        if verb not in source:
            failures.append(f"components/CalendarSource.qml: missing {verb} protocol owner")
        for path in SHIPPED:
            if path.name == "CalendarSource.qml" or f'"{verb}"' not in path.read_text():
                continue
            # The one exception: removing a CalDAV source is a Service
            # transaction, so the password clear it owes outlives the island
            # (and the CalendarSource that exists only while it shows) and a
            # restart (it is saved as url and user). The Service composes
            # calendarCredential only as that clear; a store it merely
            # forwards for CalendarSource, holding it until that account's
            # clear is answered.
            if path.name == "Service.qml" and verb == "calendarCredential":
                continue
            failures.append(f"{path.relative_to(ROOT)}: {verb} must be owned by CalendarSource")
    sends = re.findall(r'send\("calendarCredential",\s*\{([^}]*)\}', service)
    if len(sends) != 1 or 'action: "clear"' not in sends[0] or "password" in sends[0]:
        failures.append('Service.qml: must compose calendarCredential exactly once, as a clear without a password')
    settings = (ROOT / "qml" / "Settings.js").read_text()
    pending = re.search(r'\{\s*key:\s*"calendarPendingClears"[^}]*\}', settings)
    if not pending or 'type: "sources"' not in pending.group(0) or "internal: true" not in pending.group(0):
        failures.append('qml/Settings.js: calendarPendingClears must be an internal "sources" key (identifiers only)')
    if "delete result.calendarPendingClears" not in settings:
        failures.append("qml/Settings.js: status() must redact calendarPendingClears")
    if 'removeCalendarSource' not in service:
        failures.append("Service.qml: calendar source removal must be the Service's removeCalendarSource transaction")


# The IPC surface a local process can reach. Exactly these functions, none of
# which accepts an action string; only seek accepts a bounded numeric offset,
# and hudReadout's kind and device names only select a read-only answer.
# Settings never get their own verb: every one of them travels through the
# existing configure(json), which validates against settingKeys. settings()
# and onboarding() only open the plugin's own windows.
IPC_SURFACE = {
    "status": "", "retry": "", "configure": "json: string",
    "settings": "", "onboarding": "",
    "playPause": "", "next": "", "previous": "",
    "shuffle": "", "repeat": "", "seek": "seconds: real",
    "keyboardBacklightChanged": "", "hudReadout": "kind: string, device: string",
    "timer": "minutes: int, label: string", "timerCancel": "unit: string",
}


def check_ipc_surface():
    service = (ROOT / "Service.qml").read_text()
    start = service.find("IpcHandler {")
    if start < 0:
        failures.append("Service.qml: IpcHandler not found")
        return
    depth, end = 0, start
    for index in range(start, len(service)):
        if service[index] == "{":
            depth += 1
        elif service[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    found = dict(re.findall(r"function\s+(\w+)\s*\(([^)]*)\)", service[start:end]))
    if found != IPC_SURFACE:
        failures.append(
            f"Service.qml: IPC surface is {sorted(found.items())}, expected "
            f"{sorted(IPC_SURFACE.items())}; only seek takes a bounded numeric offset and "
            f"no window, focus or presence verb is exposed")


def check_spectrum_owner():
    """Only the Service launches the spectrum capture, so its lifetime has one
    owner and one set of stop conditions."""
    service = (ROOT / "Service.qml").read_text()
    if "nookisle-spectrum" not in service:
        failures.append("Service.qml: the spectrum binary is not launched from the Service")
    for path in SHIPPED:
        if path.name != "Service.qml" and "nookisle-spectrum" in path.read_text():
            failures.append(f"{path.relative_to(ROOT)}: names the spectrum binary; "
                            f"only Service.qml may launch it")


def check_quantizer_owner():
    """Only the Panel reads the artwork palette, so the quantizer runs once per
    artwork change behind one set of gates (island mode, tint on, high
    contrast off, artwork present)."""
    if "ColorQuantizer" not in (ROOT / "Panel.qml").read_text():
        failures.append("Panel.qml: the artwork ColorQuantizer is missing")
    # The helper publishes artwork as a file:// URL. A hand-written prefix
    # test on the quantizer once admitted only bare paths, so the live tint
    # never ran; the source must use the rule Artwork.qml draws with.
    block = re.search(r"ColorQuantizer\s*\{(.*?)\n    \}", (ROOT / "Panel.qml").read_text(), re.S)
    if block and "SourceState.artworkUrl(root.artworkPath)" not in block.group(1):
        failures.append("Panel.qml: the ColorQuantizer source must use SourceState.artworkUrl")
    if "SourceState.artworkUrl(artworkPath)" not in (ROOT / "components" / "Artwork.qml").read_text():
        failures.append("components/Artwork.qml: safeSource must use SourceState.artworkUrl")
    for path in SHIPPED:
        if path.name != "Panel.qml" and "ColorQuantizer" in path.read_text():
            failures.append(f"{path.relative_to(ROOT)}: uses ColorQuantizer; "
                            f"only Panel.qml may quantize the artwork")


def check_keyboard_focus():
    """The layer's keyboard focus follows IslandKeys.keyboardFocus, whose
    summoned-island branch is Exclusive: on-demand focus never reached the
    summoned island live, so its keys went to the window underneath."""
    text = (ROOT / "Panel.qml").read_text()
    if "IslandKeys.keyboardFocus(" not in text or "WlrKeyboardFocus.Exclusive" not in text:
        failures.append("Panel.qml: the layer keyboard focus must follow IslandKeys.keyboardFocus")


PIPEWIRE_IMPORTERS = {"VolumeSource.qml", "MicSource.qml", "PrivacySource.qml"}


def check_pipewire_owners():
    """PipeWire is read by the level readout's sources and the privacy
    indicators only, each behind a Loader that is off with its feature."""
    pattern = re.compile(r"^\s*import\s+Quickshell\.Services\.Pipewire", re.M)
    for path in SHIPPED:
        if pattern.search(path.read_text()) and path.name not in PIPEWIRE_IMPORTERS:
            failures.append(f"{path.relative_to(ROOT)}: imports PipeWire; only "
                            f"{sorted(PIPEWIRE_IMPORTERS)} may")


def check_bluetooth_owner():
    """Only DeviceSource reads Bluetooth, behind a Loader that is off with
    device peeks."""
    pattern = re.compile(r"^\s*import\s+Quickshell\.Bluetooth", re.M)
    if not pattern.search((ROOT / "components/DeviceSource.qml").read_text()):
        failures.append("components/DeviceSource.qml: the Bluetooth import is missing")
    for path in SHIPPED:
        if path.name != "DeviceSource.qml" and pattern.search(path.read_text()):
            failures.append(f"{path.relative_to(ROOT)}: imports Quickshell.Bluetooth; only DeviceSource.qml may")


def check_upower_owner():
    """Only PowerSource reads the power stack, so the plugin's one UPower
    reader sits behind the Panel's island-mode, power-on Loader."""
    pattern = re.compile(r"^\s*import\s+Quickshell\.Services\.UPower", re.M)
    owner = ROOT / "components" / "PowerSource.qml"
    if not pattern.search(owner.read_text()):
        failures.append("components/PowerSource.qml: the UPower import is missing")
    for path in SHIPPED:
        if path != owner and pattern.search(path.read_text()):
            failures.append(f"{path.relative_to(ROOT)}: imports Quickshell.Services.UPower; "
                            f"only components/PowerSource.qml may")


LYRICS_URL = "https://lrclib.net/api/get"


def check_network_confined():
    """Network transfers happen only in nookisle-artwork-fetch, which is
    launched from the helper for artwork and from components/LyricsFetch.qml
    for lyrics. No shipped file may use XMLHttpRequest, the LRCLIB URL may
    appear only in LyricsSource.qml, and the plain-http:// ban stays."""
    owner = ROOT / "components" / "LyricsSource.qml"
    if LYRICS_URL not in owner.read_text():
        failures.append(f"components/LyricsSource.qml: the lyrics endpoint {LYRICS_URL} is missing")
    for path in SHIPPED:
        text = path.read_text()
        name = path.relative_to(ROOT)
        if re.search(r"\bXMLHttpRequest\b", text):
            failures.append(f"{name}: uses XMLHttpRequest; no shipped file may use XMLHttpRequest")
        # The bare host name may appear as display text (the settings row
        # names the service it contacts); a URL to it may not.
        if path != owner and "https://lrclib.net" in text:
            failures.append(f"{name}: names the LRCLIB URL; only components/LyricsSource.qml may")
        # The endpoint override exists for the tests' local fixture only.
        if path != owner and re.search(r"\bendpointUrl\b", text):
            failures.append(f"{name}: sets the lyrics endpointUrl; only the tests may")
        for number, line in enumerate(text.splitlines(), 1):
            if "http://" in line:
                failures.append(f"{name}:{number}: a plain http:// URL in shipped code")
    check_lyrics_gates()
    check_lyrics_fetch()


# The Panel's wiring is what keeps a lookup opt-in and on screen: island mode
# with the setting on, the island visible (never while locked) and expanded
# on the Lyrics view, and a source only while the UI is allowed.
LYRICS_GATES = {
    "fetcher": ["lyricsFetch"],
    "lyricsEnabled": ["root.islandMode", "root.coordinator.lyrics === true"],
    "wanted": ["root.islandVisible", "root.surface.expanded", '(root.surface.view === "home" || root.surface.view === "lyrics")'],
    "endpoint": ["root.coordinator.uiAllowed === true"],
}


def check_lyrics_gates():
    text = (ROOT / "Panel.qml").read_text()
    block = re.search(r"\n    LyricsSource \{\n(.*?)\n    \}\n", text, re.S)
    if not block:
        failures.append("Panel.qml: the LyricsSource instance is missing")
        return
    for name, terms in LYRICS_GATES.items():
        binding = re.search(rf"^\s*{name}:\s*(.+)$", block.group(1), re.M)
        if not binding:
            failures.append(f"Panel.qml: LyricsSource has no {name} binding")
            continue
        for term in terms:
            if term not in binding.group(1):
                failures.append(f"Panel.qml: LyricsSource {name} lost its gate {term}")


def check_lyrics_fetch():
    """LyricsFetch.qml wraps nookisle-artwork-fetch in a short-lived process
    with the exact argv, collects bounded stdout, and kills the child on cancel()."""
    path = ROOT / "components" / "LyricsFetch.qml"
    if not path.is_file():
        failures.append("components/LyricsFetch.qml: missing component")
        return
    text = path.read_text()
    if 'Qt.resolvedUrl("../libexec/nookisle-artwork-fetch")' not in text:
        failures.append("components/LyricsFetch.qml: must resolve libexec/nookisle-artwork-fetch via Qt.resolvedUrl")
    if '"--lyrics"' not in text:
        failures.append("components/LyricsFetch.qml: argv must pass '--lyrics'")
    if "StdioCollector" not in text:
        failures.append("components/LyricsFetch.qml: must collect stdout with StdioCollector")
    if "process.signal(9)" not in text:
        failures.append("components/LyricsFetch.qml: cancel must kill the child with signal(9)")


def check_island_content_free():
    """The island's Home is its own player: IslandContent serves only the
    legacy panel, with no island-only path left in it."""
    content = (ROOT / "components" / "IslandContent.qml").read_text()
    if re.search(r"\bartGestures\b|\bheroArtGesture\b", content):
        failures.append("components/IslandContent.qml: an island-only path is back")
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    if re.search(r"^\s*IslandContent\s*\{", surface, re.M):
        failures.append("components/IslandSurface.qml: the island hosts IslandContent again; Home is HomeView")


def check_hud_input_growth():
    """The window's input region is the notch body plus, while a readout with
    a bar shows, that readout.
    It is one of three nested Regions, alongside the drag catch and optional
    hover zones, and
    jumps without animation."""
    panel = (ROOT / "Panel.qml").read_text()
    mask = re.search(r"\n        mask: Region \{\n(.*?)\n        \}\n", panel, re.S)
    if not mask:
        failures.append("Panel.qml: the window mask is missing")
    else:
        nested = re.findall(r"\bRegion\s*\{(.*?)\}", mask.group(1), re.S)
        if len(nested) != 3 or "surface.hudHitShape" not in nested[0] or "Intersection.Combine" not in nested[0]:
            failures.append("Panel.qml: the HUD input growth must be a union Region on surface.hudHitShape")
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    block = re.search(r"\n    Item \{\n        id: hudHitShape\n(.*?)\n    \}\n", surface, re.S)
    if not block:
        failures.append("components/IslandSurface.qml: the HUD input rectangle (hudHitShape) is missing")
    elif re.search(r"\bBehavior\b|Animation\b", block.group(1)):
        failures.append("components/IslandSurface.qml: the HUD input rectangle must jump, never animate")
    if "onPointChanged: if (hovered) root.trackHoverPoint(point.position, point.pressedButtons)" not in surface:
        failures.append("components/IslandSurface.qml: every hover move must pass its pressed buttons to the dwell")
    if not re.search(r"value: root\.islandMode && !hudModel\.held", panel):
        failures.append("Panel.qml: the HUD must not be suppressed while its bar is held")
    if not re.search(r'powerEnabled:.*showPowerNotifications !== false && root\.surface\.settings\.powerStyle === "peek"', panel, re.S):
        failures.append("Panel.qml: charger peeks show only with powerStyle \"peek\"")


def check_extra_island_windows():
    """displayMode "all" adds IslandWindow for the other screens: it never
    takes the keyboard (the primary keeps the summon), and its mask grows
    only as the primary's does, by the HUD bar, catch zone and hover strip."""
    path = ROOT / "components" / "IslandWindow.qml"
    if not path.exists():
        failures.append("components/IslandWindow.qml: the extra island window is missing")
        return
    text = path.read_text()
    if "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None" not in text:
        failures.append("components/IslandWindow.qml: an extra island must never take the keyboard")
    mask = re.search(r"\n    mask: Region \{\n(.*?)\n    \}\n", text, re.S)
    nested = re.findall(r"\bRegion\s*\{(.*?)\}", mask.group(1), re.S) if mask else []
    if not mask or len(nested) != 3 or "surface.hudHitShape" not in nested[0] or "surface.catchZone" not in nested[1] or "surface.hoverExtension" not in nested[2]:
        failures.append("components/IslandWindow.qml: the mask may grow only by the HUD bar, catch zone and hover strip")
    if "when: !surface.hudHeldHere" not in text:
        failures.append("components/IslandWindow.qml: only this island's own held HUD bar may latch its fullscreen")
    if "when: !root.hudHeld" not in (ROOT / "Panel.qml").read_text() or "hudHeld: root.surface.hudHeldHere" not in (ROOT / "Panel.qml").read_text():
        failures.append("Panel.qml: only the primary's own held HUD bar may latch its fullscreen")
    # Every binding Panel.qml gives an extra window names a property the
    # window declares (a missing one fails the whole Panel at load time, and
    # no offscreen suite instantiates it), and the extra window's surface
    # gets the same closed-notch inputs as the primary's.
    panel = (ROOT / "Panel.qml").read_text()
    block = re.search(r"\n(\s*)IslandWindow \{\n(.*?)\n\1\}\n", panel, re.S)
    if not block:
        failures.append("Panel.qml: the extra island windows are missing")
        return
    indent = block.group(1) + "    "
    declared = set(re.findall(r"^\s*(?:readonly |required )*property \S+ (\w+)", text, re.M))
    declared |= {"screenName", "visible"}
    for name in re.findall(r"^" + indent + r"(\w+):", block.group(2), re.M):
        if not re.match(r"on[A-Z]", name) and name not in declared:
            failures.append(f"Panel.qml: IslandWindow has no property '{name}'")
    for name in ("barHasClock", "batteryKind"):
        if not re.search(r"^        " + name + r":", text, re.M):
            failures.append(f"components/IslandWindow.qml: its surface must get {name} as the primary's does")
    if panel.count("barHasClock: root.barHasClock") != 2 or "batteryKind: batteryModel.bannerKind" not in panel:
        failures.append("Panel.qml: the primary surface and the extra windows must get barHasClock, and the primary batteryKind")


def check_view_names():
    """Home replaced "player": no shipped surface opens or names the old view,
    and the island's tabs are Home and optionally Shelf, with Lyrics a sub-view."""
    for path in (ROOT / "Panel.qml", ROOT / "components" / "IslandSurface.qml"):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r'expandTo\("player"\)|view\s*(===|=)\s*"player"', line):
                failures.append(f"{path.relative_to(ROOT)}:{number}: the \"player\" view is now \"home\"")
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    if not re.search(r'readonly property var views: settings\.shelfEnabled \? \["home", "shelf"\] : \["home"\]', surface):
        failures.append("components/IslandSurface.qml: the tabs must be Home and optionally Shelf")


# The status() keys a local process can read. Pinned, so no title, lyric,
# path or URL field can slip in unnoticed.
STATUS_KEYS = {
    "activity", "privacy",
    "timers",
    "connected", "lockReady", "panelAllowed", "controlsAllowed", "sourceCount",
    "selectionMode", "pinUnavailable", "helperRunning", "viewVisible", "viewExpanded",
    "diagnostic", "remoteArtwork", "reducedMotion", "highContrast", "island", "hud",
    "visualizer", "peek", "tint", "power", "lyrics", "shelfCount", "brightnessHud",
    "spectrum", "settings",
}


def check_status_keys():
    service = (ROOT / "Service.qml").read_text()
    match = re.search(r"function\s+status\(\)[^{]*\{\s*return\s+JSON\.stringify\(\{(.*?)\}\)", service, re.S)
    if not match:
        failures.append("Service.qml: status() object literal not found")
        return
    found = set(re.findall(r"(\w+)\s*:", match.group(1)))
    if found != STATUS_KEYS:
        failures.append(f"Service.qml: status() keys differ from the pinned set: "
                        f"extra {sorted(found - STATUS_KEYS)}, missing {sorted(STATUS_KEYS - found)}")


def check_shelf_processes():
    """Shelf file actions run only through components/ShelfActions.qml, as
    argument arrays and never through a shell. PowerSource retains its
    existing, separately gated power-command launch, and SystemActions its
    fixed Omarchy reminder and recording commands."""
    actions = ROOT / "components" / "ShelfActions.qml"
    power = ROOT / "components" / "PowerSource.qml"
    if not actions.exists():
        failures.append("components/ShelfActions.qml is missing")
        return
    text = actions.read_text()
    if re.search(r'"(?:ba|z|da)?sh"\s*,\s*"-c"', text):
        failures.append("components/ShelfActions.qml: runs a command through a shell")
    if "timeoutMs: 30000" not in text.replace("readonly property int ", ""):
        failures.append("components/ShelfActions.qml: the 30 s process timeout is missing")
    if power.read_text().count("Quickshell.execDetached(root.powerCommand)") != 1:
        failures.append("components/PowerSource.qml: expected the existing power-command launch")
    system = ROOT / "components" / "SystemActions.qml"
    launches = re.findall(r"execDetached\((\[[^\]]*\])", system.read_text())
    programs = sorted(set(re.findall(r'^\["([^"]+)"', launch)[0] for launch in launches if launch.startswith('["')))
    if len(launches) != 4 or programs != ["omarchy-capture-screenrecording", "omarchy-reminder", "rm", "systemctl"]:
        failures.append("components/SystemActions.qml: launches only omarchy-reminder, systemctl, rm and "
                        "omarchy-capture-screenrecording, each as an argument array with a fixed program")
    for path in [ROOT / "Service.qml", ROOT / "Panel.qml", *sorted((ROOT / "components").glob("*.qml"))]:
        if path not in (actions, power, system) and "execDetached" in path.read_text():
            failures.append(f"{path.relative_to(ROOT)}: launches a detached process outside the action owners")


def check_catch_zone():
    """The drag catch zone is drop-only and part of the input region. It
    holds a DropArea and nothing that turns pointer use of the empty bar
    centre into island gestures, never animates its size, and Panel.qml
    unions it with the body in the layer mask."""
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    start, end = surface.find("id: catchZone"), surface.find("id: hitShape")
    if start < 0 or end < start:
        failures.append("IslandSurface.qml: the catch zone item must precede hitShape")
        return
    block = surface[start:end]
    if "DropArea" not in block:
        failures.append("IslandSurface.qml: the catch zone must hold a DropArea")
    for handler in ("HoverHandler", "TapHandler", "WheelHandler", "DragHandler", "MouseArea", "Behavior"):
        if handler in block:
            failures.append(f"IslandSurface.qml: the catch zone must not hold a {handler}")
    panel = (ROOT / "Panel.qml").read_text()
    mask = re.search(r"\n        mask: Region \{\n(.*?)\n        \}\n", panel, re.S)
    nested = re.findall(r"\bRegion\s*\{(.*?)\}", mask.group(1), re.S) if mask else []
    if len(nested) != 3 or "surface.catchZone" not in nested[1] or "Intersection.Combine" not in nested[1]:
        failures.append("Panel.qml: the layer mask must union the catch zone in its own Region")


def check_hover_extension():
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    match = re.search(r"id: hoverExtension\n(.*?)\n    \}\n    readonly property alias hoverExtension", surface, re.S)
    if not match or "settings.extendHoverArea" not in match.group(1) or "HoverHandler" not in match.group(1):
        failures.append("components/IslandSurface.qml: the optional hover strip must be a hover-only region")
    elif any(name in match.group(1) for name in ("TapHandler", "WheelHandler", "DragHandler", "MouseArea")):
        failures.append("components/IslandSurface.qml: the hover strip must not handle taps, wheels or drags")
    for name in ("Panel.qml", "components/IslandWindow.qml"):
        if "surface.hoverExtension" not in (ROOT / name).read_text():
            failures.append(f"{name}: the hover strip must be included in the input mask")


def check_status_settings():
    """Stored values are schema-resolved; status redacts source locations."""
    service = (ROOT / "Service.qml").read_text()
    match = re.search(r"function\s+status\(\)[^{]*\{\s*return\s+JSON\.stringify\(\{(.*?)\}\)", service, re.S)
    if not match or not re.search(r"\bsettings:\s*Settings\.publicValues\(root\.fileSettings\)", match.group(1)):
        failures.append("Service.qml: status() must redact calendar source settings")
    assignments = re.findall(r"\bfileSettings\s*(?::|=(?!=))\s*([^\n]*)", service)
    if not assignments:
        failures.append("Service.qml: fileSettings is never assigned")
    for value in assignments:
        if not value.startswith("Settings.resolve("):
            failures.append(f"Service.qml: fileSettings is set to '{value.strip()}' without Settings.resolve")
    resolve = re.search(r"function resolve\(values(?:,\s*notes)?\)\s*\{(.*?)\n\}", (ROOT / "qml" / "Settings.js").read_text(), re.S)
    if not resolve or 'spec.store !== "file"' not in resolve.group(1):
        failures.append("qml/Settings.js: resolve() must keep exactly the file-store keys")
    if not any(store == "file" for _, store in schema_entries()):
        failures.append("qml/Settings.js: no file-store key; status().settings would be empty")


def check_calendar_ui():
    """The calendar UI never handles a credential itself: a CalDAV password
    goes from the editor straight to CalendarSource.storeCredential, which
    hands it to the helper (and secret-tool's stdin); no QML names
    secret-tool. Only the calendar panel opens a source externally, and only
    a local file or folder."""
    editor = (ROOT / "components" / "CalendarSourceEditor.qml").read_text()
    if "source.storeCredential(" not in editor:
        failures.append("components/CalendarSourceEditor.qml: passwords must go through source.storeCredential")
    if re.search(r"configure\([^)]*password", editor):
        failures.append("components/CalendarSourceEditor.qml: a password must never reach configure()")
    for path in SHIPPED:
        text = path.read_text()
        if path.suffix == ".qml" and "secret-tool" in text:
            failures.append(f"{path.relative_to(ROOT)}: names secret-tool; only the helper runs it")
        if "openUrlExternally" in text and path.name not in ("CalendarPanel.qml", "SettingsPane.qml"):
            failures.append(f"{path.relative_to(ROOT)}: opens URLs externally outside the calendar and project link")
    pane = (ROOT / "components" / "SettingsPane.qml").read_text()
    if "Qt.openUrlExternally(root.repositoryUrl)" not in pane or "bavanchun\\/nookisle" not in pane:
        failures.append("components/SettingsPane.qml: project link must use the validated repository URL")


def check_power_notification_switch():
    """The notification switch gates both presentation routes while the
    power source remains available to the header gauge."""
    panel = (ROOT / "Panel.qml").read_text()
    for owner in ("powerEnabled:", "enabled:"):
        if not re.search(rf"{owner}[^\n]*\n\s*&& root\.surface\.settings\.showPowerNotifications !== false", panel):
            failures.append(f"Panel.qml: {owner} must honour showPowerNotifications")
    if not re.search(r"id: powerLoader\s+active:[^\n]*root\.coordinator\.power === true", panel):
        failures.append("Panel.qml: the power source must remain active for the gauge")


def check_custom_accent_route():
    panel = (ROOT / "Panel.qml").read_text()
    service = (ROOT / "Service.qml").read_text()
    surface = (ROOT / "components" / "IslandSurface.qml").read_text()
    for name, text in (("Panel.qml", panel), ("Service.qml", service)):
        if "customAccent:" not in text or "useCustomAccentColor" not in text:
            failures.append(f"{name}: the chosen accent must reach its DesignTokens")
    if "ink.accent = tokens.accent" not in surface:
        failures.append("components/IslandSurface.qml: the black notch must use the chosen accent")


def check_volume_load_baseline():
    """The first ready sink sample must reach the HUD after Loader.item binds."""
    panel = (ROOT / "Panel.qml").read_text()
    loader = re.search(r"id: volumeLoader\b(.*?)\n    \}", panel, re.S)
    if not loader or not re.search(r"onLoaded:\s*\{[^}]*hudModel\.resetBaselines\(\);[^}]*volumeLoader\.item\.emit\(\)", loader.group(1), re.S):
        failures.append("Panel.qml: volume loader must send the ready sink baseline after resetting it")
    source = (ROOT / "components" / "VolumeSource.qml").read_text()
    if "Component.onCompleted: emit()" in source:
        failures.append("VolumeSource.qml: completed emission precedes the loader's sample connection")
    if "VolumeSink.resolve(Pipewire.defaultAudioSink, Pipewire.linkGroups.values)" not in source:
        failures.append("VolumeSource.qml: the HUD must resolve the same downstream sink as volume keys")
    for method in ("adjust", "setVolume"):
        block = re.search(r"function " + method + r"\([^)]*\)\s*\{(.*?)\n    \}", source, re.S)
        if not block or "root.sink.audio.volume" not in block.group(1):
            failures.append("VolumeSource.qml: " + method + " must write the resolved sink")


def check_calendar_stays_configured_while_hidden():
    service = (ROOT / "Service.qml").read_text()
    loader = re.search(r"id: calendarLoader\b(.*?)\n    \}", service, re.S)
    if not loader or "root.islandShowing" in loader.group(1):
        failures.append("Service.qml: hiding the island must keep the calendar source configured")
    send = re.search(r"function calendarSend\(type, fields\)\s*\{(.*?)\n    \}", service, re.S)
    if not send or "!islandShowing" in send.group(1):
        failures.append("Service.qml: the hidden calendar source must still be able to request windows")


def check_invalid_settings_backup():
    service = (ROOT / "Service.qml").read_text()
    writer = re.search(r"function writeFileSettings\(values\)\s*\{(.*?)\n    \}", service, re.S)
    if not writer or "settingsBackupFile.setData(settingsBackupData)" not in writer.group(1) or writer.group(1).find("settingsBackupFile.setData") > writer.group(1).find("settingsFile.setText"):
        failures.append("Service.qml: preserve invalid settings bytes before replacing settings.json")
    if 'console.warn("nookisle: invalid settings.json' not in service:
        failures.append("Service.qml: an invalid settings reset must be logged")


def quickshell_signals():
    """Each exported Quickshell QML type's signals, its base classes' included,
    read from the installed qmltypes; None when Quickshell is not installed."""
    paths = [pathlib.Path(p) for p in os.environ.get("QML_IMPORT_PATH", "").split(os.pathsep) if p]
    paths += [pathlib.Path("/usr/lib/qt6/qml"), pathlib.Path("/usr/lib64/qt6/qml"),
              ROOT / "tests/fixtures/qmltypes"]
    roots = [path / "Quickshell" for path in paths if (path / "Quickshell").is_dir()]
    if not roots:
        return None
    components, exported = {}, {}
    for qmltypes in roots[0].rglob("*.qmltypes"):
        for block in re.split(r"\n    Component \{", qmltypes.read_text())[1:]:
            name = re.search(r'\n\s*name: "([^"]+)"', block)
            if not name:
                continue
            prototype = re.search(r'\n\s*prototype: "([^"]+)"', block)
            components[name[1]] = (prototype[1] if prototype else None,
                                   set(re.findall(r'Signal \{ name: "([^"]+)"', block)))
            for exports in re.findall(r"exports: \[([^\]]*)\]", block):
                for qml_name in re.findall(r'"Quickshell[^"/]*/([A-Za-z]+) [\d.]+"', exports):
                    exported.setdefault(qml_name, name[1])
    signals = {}
    for qml_name, component in exported.items():
        seen = set()
        while component in components and component not in seen:
            seen.add(component)
            prototype, own = components[component]
            signals.setdefault(qml_name, set()).update(own)
            component = prototype
    return signals


def check_window_signals():
    """A root object must not redeclare a signal its Quickshell type already
    has: the engine warns "Duplicate signal name" at every shell start, and a
    handler can bind to the wrong one."""
    signals = quickshell_signals()
    if signals is None:
        return
    for path in SHIPPED:
        if path.suffix != ".qml":
            continue
        text = path.read_text()
        root = re.search(r"^([A-Z][A-Za-z0-9_]*)\s*\{", text, re.M)
        if not root or root[1] not in signals:
            continue
        for name in re.findall(r"^    signal\s+(\w+)", text, re.M):
            if name in signals[root[1]]:
                failures.append(f"{path.relative_to(ROOT)}: signal {name} duplicates {root[1]}'s own {name} signal")


def check_plain_text_contract():
    """Webpage-controlled MPRIS/Chrome/CalDAV text rendered as RichText/AutoText
    is blocked by marketplace security. All dynamic text must set PlainText."""
    banned = re.compile(r"\b(RichText|StyledText|AutoText|MarkdownText)\b")
    for path in SHIPPED:
        if path.suffix != ".qml":
            continue
        for num, line in enumerate(path.read_text().splitlines(), 1):
            if banned.search(line):
                failures.append(f"{path.relative_to(ROOT)}:{num}: banned text format in marketplace review")

    marquee = (ROOT / "components" / "Marquee.qml").read_text()
    if marquee.count("textFormat: Text.PlainText") < 2:
        failures.append("components/Marquee.qml: both internal Text items must enforce textFormat: Text.PlainText")
    tooltip = (ROOT / "components" / "IslandToolTip.qml").read_text()
    if "textFormat: Text.PlainText" not in tooltip:
        failures.append("components/IslandToolTip.qml: contentItem must enforce textFormat: Text.PlainText")

    target_types = {"Text", "Label", "TextEdit", "TextArea", "ToolTip"}
    pattern = re.compile(r"\b(" + "|".join(target_types) + r")\s*\{")
    for path in SHIPPED:
        if path.suffix != ".qml":
            continue
        content = path.read_text()
        for m in pattern.finditer(content):
            type_name = m.group(1)
            start = m.end()
            depth, pos = 1, start
            while pos < len(content) and depth > 0:
                if content[pos] == "{":
                    depth += 1
                elif content[pos] == "}":
                    depth -= 1
                pos += 1
            body = content[start:pos-1]
            line_num = content.count("\n", 0, m.start()) + 1

            d = 0
            i = 0
            has_format = False
            in_line_comment = False
            in_block_comment = False
            in_quote = None
            text_matches = []

            while i < len(body):
                ch = body[i]
                next_ch = body[i+1] if i + 1 < len(body) else ""

                if in_line_comment:
                    if ch == "\n":
                        in_line_comment = False
                    i += 1
                    continue
                if in_block_comment:
                    if ch == "*" and next_ch == "/":
                        in_block_comment = False
                        i += 2
                        continue
                    i += 1
                    continue
                if in_quote:
                    if ch == "\\":
                        i += 2
                        continue
                    if ch == in_quote:
                        in_quote = None
                    i += 1
                    continue

                if ch == "/" and next_ch == "/":
                    in_line_comment = True
                    i += 2
                    continue
                if ch == "/" and next_ch == "*":
                    in_block_comment = True
                    i += 2
                    continue
                if ch in ("\"", "\x27"):
                    in_quote = ch
                    i += 1
                    continue

                if d == 0:
                    tf_match = re.match(r"(?<![\w.])textFormat\s*:\s*(Text|TextEdit)\.PlainText\b", body[i:])
                    if tf_match:
                        has_format = True
                    t_match = re.match(r"(?<![\w.])text\s*:", body[i:])
                    if t_match:
                        text_matches.append(i + t_match.end())

                if ch == "{":
                    d += 1
                elif ch == "}":
                    d -= 1
                i += 1

            for expr_pos in text_matches:
                while expr_pos < len(body):
                    if body[expr_pos] in " \t\r\n":
                        expr_pos += 1
                    elif body[expr_pos:expr_pos+2] == "//":
                        nl = body.find("\n", expr_pos)
                        expr_pos = len(body) if nl == -1 else nl + 1
                    elif body[expr_pos:expr_pos+2] == "/*":
                        end_c = body.find("*/", expr_pos)
                        expr_pos = len(body) if end_c == -1 else end_c + 2
                    else:
                        break
                if expr_pos >= len(body):
                    continue
                if body[expr_pos] == "{":
                    if not has_format:
                        failures.append(f"{path.relative_to(ROOT)}:{line_num}: {type_name} with block-bodied text must set textFormat: PlainText")
                else:
                    exp_start = expr_pos
                    p_depth = 0
                    b_depth = 0
                    while expr_pos < len(body):
                        c = body[expr_pos]
                        if c == "(": p_depth += 1
                        elif c == ")": p_depth -= 1
                        elif c == "[": b_depth += 1
                        elif c == "]": b_depth -= 1
                        elif c == "{" and p_depth == 0 and b_depth == 0:
                            break
                        elif c == ";" and p_depth == 0 and b_depth == 0:
                            break
                        elif c == "\n" and p_depth == 0 and b_depth == 0:
                            rest = body[expr_pos+1:].lstrip()
                            if rest and rest[0] in "+-?:|&.,":
                                expr_pos += 1
                                continue
                            prev = body[exp_start:expr_pos].rstrip()
                            if prev and prev[-1] in "+-?:|&.,":
                                expr_pos += 1
                                continue
                            break
                        expr_pos += 1
                    expr_str = body[exp_start:expr_pos].strip()
                    is_literal = bool(re.match(r"^(\"[^\"]*\"|\x27[^\x27]*\x27)\s*;?$", expr_str))
                    if not is_literal and not has_format:
                        failures.append(f"{path.relative_to(ROOT)}:{line_num}: {type_name} with dynamic text must set textFormat: PlainText")


def check_single_manifest():
    """Marketplace catalog builder enforces a single manifest.json at depth <= 1."""
    out = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True)
    manifest_re = re.compile(r"^([^/]+/)?manifest\.json$")
    matches = [line for line in out.splitlines() if manifest_re.match(line)]
    if matches != ["manifest.json"]:
        failures.append(f"single-manifest violation: found {matches}, expected only ['manifest.json']")


def check_untrusted_url_contract():
    """External openers and Image sources must load only validated local files
    or anchored, trusted URLs."""
    for path in SHIPPED:
        if path.suffix != ".qml":
            continue
        text = path.read_text()
        if "gio open" in text:
            failures.append(f"{path.relative_to(ROOT)}: gio open is forbidden")
        if "openUrlExternally" in text and path.name not in ("CalendarPanel.qml", "SettingsPane.qml"):
            failures.append(f"{path.relative_to(ROOT)}: openUrlExternally outside CalendarPanel and SettingsPane")

    cal_js = (ROOT / "qml" / "Calendar.js").read_text()
    if "isRemote(source.kind)" not in cal_js:
        failures.append("qml/Calendar.js: openTarget must reject remote sources")

    ss_js = (ROOT / "qml" / "SourceState.js").read_text()
    if "file:///" not in ss_js:
        failures.append("qml/SourceState.js: artworkUrl must reject non-file URLs")

    settings_js = (ROOT / "qml" / "Settings.js").read_text()
    if not re.search(r'key:\s*"remoteArtwork"[^}]*default:\s*false', settings_js):
        failures.append("qml/Settings.js: remoteArtwork must default to false")


def check_settings_atomic_0600_ordering():
    """Settings file writes must be refused until the 0600 file exists on disk.
    settingsDirReady cannot become true in settingsDirProcess, but only after
    settingsInitProcess exits 0."""
    service_text = (ROOT / "Service.qml").read_text()
    m_dir = re.search(r"id:\s*settingsDirProcess\b[\s\S]*?(?=id:|$)", service_text)
    if not m_dir:
        failures.append("Service.qml: settingsDirProcess not found")
    elif re.search(r"settingsDirReady\s*=\s*(true|exitCode\s*===\s*0)", m_dir.group(0)):
        failures.append("Service.qml: settingsDirProcess must not set settingsDirReady before settingsInitProcess completes")

    m_init = re.search(r"id:\s*settingsInitProcess\b[\s\S]*?(?=(?:Process|FileView|Component|IpcHandler)\s*\{|$)", service_text)
    if not m_init:
        failures.append("Service.qml: settingsInitProcess not found")
    elif not re.search(r"onExited:\s*\([^)]*\)\s*=>\s*\{[\s\S]*?settingsDirReady\s*=\s*exitCode\s*===\s*0", m_init.group(0)):
        failures.append("Service.qml: settingsInitProcess.onExited must set settingsDirReady on exitCode === 0")

    if not re.search(r"function\s+prepareSettingsDir\(\)\s*\{[\s\S]*?!settingsInitProcess\.running", service_text):
        failures.append("Service.qml: prepareSettingsDir must not restart while settingsInitProcess is running")

    if not re.search(r"function\s+writeFileSettings\([^)]*\)\s*\{[\s\S]*?if\s*\(!settingsDirReady\)", service_text):
        failures.append("Service.qml: writeFileSettings must guard file writes with !settingsDirReady")


def main():
    check_no_vietnamese()
    check_no_gpu_only_paths()
    check_gpu_effects_gated()
    check_no_recurring_ui_timer()
    check_absolute_positions_removed()
    check_production_properties()
    check_window_signals()
    check_hud_readout_suppression()
    check_media_key_readout_ownership()
    check_service_imports()
    check_camera_import_owner()
    check_camera_gate()
    check_brightness_owner()
    check_status_redaction()
    check_calendar_boundary()
    check_catch_zone_tradeoff_documented()
    check_calendar_url_credentials()
    check_calendar_ui()
    check_power_notification_switch()
    check_custom_accent_route()
    check_volume_load_baseline()
    check_calendar_stays_configured_while_hidden()
    check_invalid_settings_backup()
    check_ipc_surface()
    check_setting_keys()
    check_lyrics_opt_in()
    check_finite_motion()
    check_spectrum_owner()
    check_quantizer_owner()
    check_keyboard_focus()
    check_pipewire_owners()
    check_bluetooth_owner()
    check_upower_owner()
    check_status_keys()
    check_status_settings()
    check_network_confined()
    check_view_names()
    check_island_content_free()
    check_hud_input_growth()
    check_extra_island_windows()
    check_shelf_processes()
    check_catch_zone()
    check_fixed_plugin_windows()
    check_hover_extension()
    check_battery_warning_banner()
    check_settings_documented()
    check_camera_order_pruned()
    check_deadlines_ignore_wall_clock()
    check_plain_text_contract()
    check_single_manifest()
    check_untrusted_url_contract()
    check_settings_atomic_0600_ordering()
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print(f"source contract ok ({len(SHIPPED)} files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
