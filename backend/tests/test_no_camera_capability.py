"""No-camera capability and microphone-policy scan (S9, guide §9 / SPEC §10).

The product is camera-free and has no hidden background recording. This test reads
the Android app manifest (plus any declared Flutter plugin manifests) and the
Windows runner sources:

* no camera permission, camera hardware feature or camera API reference;
* the microphone permission is supplied (directly or by the declared ``record``
  plugin, whose manifest declares ``RECORD_AUDIO``);
* no service declares background/foreground microphone recording.

It is a static scan, so it runs without Flutter or a device.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable
from urllib.parse import unquote, urlparse

REPO_ROOT = Path(__file__).resolve().parents[2]  # anchor/
MOBILE = REPO_ROOT / "mobile"
ANDROID_ROOT = MOBILE / "android"
APP_MANIFEST = ANDROID_ROOT / "app" / "src" / "main" / "AndroidManifest.xml"
WINDOWS_RUNNER = MOBILE / "windows" / "runner"
PACKAGE_CONFIG = MOBILE / ".dart_tool" / "package_config.json"
PUBSPEC = MOBILE / "pubspec.yaml"

CAMERA_TOKENS = (
    "android.permission.camera",
    "android.hardware.camera",
)
WINDOWS_CAMERA_TOKENS = (
    "camera",
    "webcam",
    "mediacapture",
    "videocapture",
    "capcreatecapturewindow",
)
BACKGROUND_RECORDING_TOKENS = (
    "foreground_service_microphone",
    "foregroundservicetype=\"microphone\"",
    "foregroundservicetype='microphone'",
)
MICROPHONE_PERMISSION = "android.permission.record_audio"
TEXT_SUFFIXES = {".cpp", ".h", ".hpp", ".c", ".cc", ".manifest", ".rc", ".txt", ".cmake"}
XML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
C_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.DOTALL)


def _android_text(path: Path) -> str:
    return XML_COMMENT.sub("", path.read_text(encoding="utf-8"))


def _windows_text(text: str) -> str:
    return C_COMMENT.sub("", text)


def _android_manifests() -> list[Path]:
    manifests = sorted(ANDROID_ROOT.rglob("AndroidManifest.xml"))
    assert APP_MANIFEST in manifests, f"missing Android app manifest: {APP_MANIFEST}"
    return manifests


def _plugin_manifests() -> list[Path]:
    """Android manifests of declared Flutter plugins, resolved from package_config."""
    if not PACKAGE_CONFIG.exists():
        return []
    try:
        payload = json.loads(PACKAGE_CONFIG.read_text(encoding="utf-8"))
    except (OSError, ValueError):  # pragma: no cover - corrupt tool cache
        return []
    manifests: list[Path] = []
    for package in payload.get("packages", []):
        root_uri = str(package.get("rootUri", ""))
        if not root_uri.startswith("file:"):
            continue
        raw_path = unquote(urlparse(root_uri).path)
        # Windows file URIs look like file:///C:/... -> "/C:/..." after parsing.
        if re.match(r"^/[A-Za-z]:", raw_path):
            raw_path = raw_path[1:]
        root = Path(raw_path)
        if not root.is_dir():
            continue
        manifests.extend(root.glob("android/src/main/AndroidManifest.xml"))
    return manifests


def _windows_runner_texts() -> Iterable[tuple[Path, str]]:
    assert WINDOWS_RUNNER.is_dir(), f"missing Windows runner: {WINDOWS_RUNNER}"
    for path in sorted(WINDOWS_RUNNER.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        yield path, _windows_text(path.read_text(encoding="utf-8", errors="replace"))


def test_no_camera_permission_or_feature_in_android_manifests():
    for manifest in _android_manifests():
        lowered = _android_text(manifest).lower()
        for token in CAMERA_TOKENS:
            assert token not in lowered, f"{manifest} requests {token!r}"


def test_no_camera_api_in_windows_runner():
    for path, text in _windows_runner_texts():
        lowered = text.lower()
        for token in WINDOWS_CAMERA_TOKENS:
            assert token not in lowered, f"{path} references {token!r}"


def test_microphone_permission_is_declared():
    app_text = _android_text(APP_MANIFEST).lower()
    plugin_manifests = _plugin_manifests()
    app_declares = MICROPHONE_PERMISSION in app_text
    plugin_declares = any(
        MICROPHONE_PERMISSION in _android_text(manifest).lower()
        for manifest in plugin_manifests
    )
    assert app_declares or plugin_declares, (
        "the app must request android.permission.RECORD_AUDIO, either directly in "
        f"{APP_MANIFEST} or through the declared record plugin"
    )
    # The microphone plugin is the product's only audio path; keep it explicit.
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    assert "record:" in pubspec or app_declares


def test_no_background_recording_service():
    manifests = _android_manifests() + _plugin_manifests()
    for manifest in manifests:
        lowered = _android_text(manifest).lower()
        for token in BACKGROUND_RECORDING_TOKENS:
            assert token not in lowered, f"{manifest} declares background microphone use"
        assert "<service" not in lowered, f"{manifest} must not declare a background service"
