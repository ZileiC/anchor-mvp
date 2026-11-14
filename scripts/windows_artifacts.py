"""Check a frozen backend and assemble a Windows ZIP from build outputs only."""

from __future__ import annotations

import argparse
import re
from io import BytesIO
from pathlib import Path, PurePosixPath
from struct import error as StructError
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, BadZipFile, ZipFile


class ArtifactError(ValueError):
    pass


BACKEND_ENTRY = "backend/anchor_backend.exe"
RUNNER_FILES = {
    "anchor_app.exe",
    "dartjni.dll",
    "flutter_tts_plugin.dll",
    "flutter_windows.dll",
    "record_windows_plugin.dll",
    "url_launcher_windows_plugin.dll",
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "native_assets.json",
    "data/app.so",
    "data/icudtl.dat",
    "data/flutter_assets/AssetManifest.bin",
    "data/flutter_assets/AssetManifest.json",
    "data/flutter_assets/FontManifest.json",
    "data/flutter_assets/NativeAssetsManifest.json",
    "data/flutter_assets/NOTICES.Z",
    "data/flutter_assets/kernel_blob.bin",
    "data/flutter_assets/assets/images/anchor-logo.png",
    "data/flutter_assets/fonts/MaterialIcons-Regular.otf",
    "data/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf",
    "data/flutter_assets/shaders/ink_sparkle.frag",
    "data/flutter_assets/shaders/stretch_effect.frag",
}
REQUIRED_RUNNER_FILES = {"anchor_app.exe", "flutter_windows.dll", "data/icudtl.dat"}
MIGRATION = r"migrations/[0-9]{3}_[A-Za-z0-9_]+\.sql"
PYINSTALLER_SUPPORT_FILES = {
    "base_library.zip",
    "certifi/cacert.pem",
    "certifi/py.typed",
    "content/activities.json",
    "setuptools/_vendor/jaraco/text/Lorem ipsum.txt",
    # The same build command can be exercised on macOS for regression tests.
    "Python",
    "Python.framework/Python",
    "Python.framework/Resources",
    "Python.framework/Versions/Current",
}
PYINSTALLER_RESOURCES = (
    MIGRATION,
    r"[\w.+-]+\.dist-info/(?:licenses/)?"
    r"(?:INSTALLER|METADATA|RECORD|WHEEL|top_level\.txt|entry_points\.txt|LICENSE[\w.-]*)",
    r"(?:[\w.+-]+/)*[\w.+-]+\.(?:dll|pyd|dylib|so(?:\.\d+)*)",
    r"Python\.framework/Versions/\d+\.\d+/(?:Python|Resources/Info\.plist)",
)


def check_backend(executable: Path, *, sentinel: bytes | None = None) -> None:
    # PyInstaller is a build-only dependency. Its reader checks the actual
    # archive inside the executable, including compressed --add-data entries.
    from PyInstaller.archive.readers import CArchiveReader

    archive = CArchiveReader(str(executable))
    entries = {name.replace("\\", "/") for name in archive.toc}
    if "content/activities.json" not in entries or not any(
        re.fullmatch(MIGRATION, name) for name in entries
    ):
        raise ArtifactError("Backend executable is missing Anchor's build resources.")

    for name, (*_, kind) in archive.toc.items():
        archive_name = name.replace("\\", "/")
        parts = archive_name.split("/")
        if any(not part or part.endswith((" ", ".")) or ":" in part for part in parts):
            raise ArtifactError("Backend executable contains an invalid archive path.")
        # The PyInstaller Windows writer can mark data as binary, so check
        # the destination name even for entries whose type code is 'b'.
        module = kind in {"m", "M", "s", "z"} and name.removesuffix(".pyz").isidentifier()
        zone = archive_name.startswith("tzdata/zoneinfo/") and (
            PurePosixPath(archive_name).suffix in {"", ".tab", ".zi", ".list"}
            and re.fullmatch(r"tzdata/zoneinfo/[A-Za-z0-9_+./-]+", archive_name)
        )
        allowed = (
            module
            or zone
            or archive_name in PYINSTALLER_SUPPORT_FILES
            or any(re.fullmatch(pattern, archive_name) for pattern in PYINSTALLER_RESOURCES)
        )
        if not allowed:
            raise ArtifactError("Backend executable contains an unapproved archive entry.")
        if sentinel:
            payload = archive.extract(name)
            found = sentinel in payload
            if not found and kind == "z":
                modules = archive.open_embedded_archive(name)
                found = any(
                    sentinel in (modules.extract(module, raw=True) or b"")
                    for module in modules.toc
                )
            if not found and archive_name == "base_library.zip":
                with ZipFile(BytesIO(payload)) as library:
                    found = any(sentinel in library.read(entry) for entry in library.namelist())
            if found:
                raise ArtifactError("Backend executable contains the test sentinel.")
    if sentinel and sentinel in executable.read_bytes():
        raise ArtifactError("Backend executable contains the test sentinel.")


def package_windows(runner: Path, backend: Path, readme: Path, output: Path) -> None:
    """Select known runner outputs and validate the nested backend before publishing the ZIP."""
    check_backend(backend)
    with TemporaryDirectory(dir=output.parent, prefix="anchor-package-") as directory:
        temporary = Path(directory)
        zip_path = temporary / output.name
        with ZipFile(zip_path, "w", compression=ZIP_DEFLATED) as archive:
            for name in sorted(RUNNER_FILES):
                source = runner / name
                if not source.is_file():
                    continue
                if source.resolve() != runner.resolve() / name:
                    raise ArtifactError("Runner output must use regular files inside its build directory.")
                archive.write(source, name)
            archive.write(backend, BACKEND_ENTRY)
            archive.write(readme, "README-DEMO.txt")

        with ZipFile(zip_path) as archive:
            names = set(archive.namelist())
            required = REQUIRED_RUNNER_FILES | {BACKEND_ENTRY, "README-DEMO.txt"}
            if not required <= names or not names & {"data/app.so", "data/flutter_assets/kernel_blob.bin"}:
                raise ArtifactError("Windows ZIP is missing required runner files.")
            if not names <= RUNNER_FILES | {BACKEND_ENTRY, "README-DEMO.txt"}:
                raise ArtifactError("Windows ZIP contains an unapproved file.")
            # Inspect the copy that went into the ZIP, including for -SkipBuild.
            check_backend(Path(archive.extract(BACKEND_ENTRY, temporary)))
        zip_path.replace(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend", type=Path)
    parser.add_argument("--zip", type=Path)
    parser.add_argument("--runner", type=Path)
    parser.add_argument("--readme", type=Path)
    args = parser.parse_args()
    try:
        if args.zip is None:
            check_backend(args.backend)
        else:
            if args.runner is None or args.readme is None:
                parser.error("--zip requires --runner and --readme")
            package_windows(args.runner, args.backend, args.readme, args.zip)
    except ArtifactError as error:
        parser.exit(1, f"Artifact check failed. {error}\n")
    except (BadZipFile, ImportError, OSError, ValueError, RuntimeError, StructError):
        # Never dump archive entries, paths or parser exceptions to build logs.
        parser.exit(1, "Artifact check failed. Install the build dependencies and rebuild from source.\n")
    print("Artifact check passed.")


if __name__ == "__main__":
    main()
