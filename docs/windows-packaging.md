# Windows packaging and credential recovery

## If you built or downloaded an earlier Windows package

Older builds could include the local provider credential file inside the PyInstaller
executable. If your provider account supplied keys for an affected build, revoke those
keys in the provider dashboard now. Rotate any other credential put in the same file,
including a separate speech-output key if one was configured. Check usage and billing
from the first affected publication. Configure replacement keys only on the test machine
after unpacking a clean build.

The repository owner should withdraw affected release assets and shared ZIPs, tell recipients
to discard their old copies, and review forks, tags and other distribution locations.
Replacing the current build does not remove earlier Git objects or downloads. Coordinate
any history cleanup with the owner and collaborators after rotation.
[GitHub credential-exposure guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)

## Build and verify a replacement locally on Windows

Use a clean checkout of the reviewed fix, with Python, Flutter, and the Windows toolchain
available. The output stays in `mobile/dist`. Packaging no longer refreshes a tracked
`release/windows` folder. The old source download no longer includes the affected backend.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows.ps1 -Version clean-review
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_backend_exe.ps1 -SkipNetworkSpeech
Get-FileHash -Algorithm SHA256 backend/dist/anchor_backend.exe
Get-FileHash -Algorithm SHA256 mobile/dist/AnchorDemo-clean-review.zip
```

The build checks the PyInstaller table of contents. Packaging selects approved Flutter
runner files, rechecks the backend even with `-SkipBuild`, checks the copy inside the ZIP,
and only publishes the local ZIP path after validation. Run the smoke test before
distribution. Unpack the verified ZIP to a new directory and check Windows desktop
startup, local database creation, phone login and phone AI setup on the demo LAN.
Then try a real chat and transcription with replacement demo keys. Use
`scripts/test_backend_exe.ps1` without `-SkipNetworkSpeech` for the existing live
Edge speech check. Record the commit, both hashes and the Windows smoke result before
replacing a shared download.

Run the security regression tests with `backend/requirements-build.txt` installed in the
Python environment and PowerShell on PATH.

```powershell
python -m pytest backend/tests/test_windows_artifacts.py backend/tests/test_bundle_credentials.py -q
```

The tests plant synthetic credentials, inspect the generated executable including
compressed entries, exercise the ZIP script with synthetic runner data, and start a
fresh frozen backend before configuring providers through the linked caregiver's API.
The fixture-based ZIP test does not establish that Flutter's native Windows output runs.

## Set providers after installation

On the trusted demo LAN, use the phone's AI setup page to save ASR and LLM keys. The backend
stores them in its local SQLite database and rebuilds the adapters. A fresh installation
can launch with offline chat and Windows System.Speech recognition where available.

For operator setup, set the existing `ANCHOR_*` variables before launch, place
`config/credentials.env` beside the **backend executable**, or point
`ANCHOR_DEMO_CREDENTIALS` at an external file. For example, the installed ZIP layout
uses `backend/config/credentials.env`. Use the existing environment or local file to
select a dedicated speech-output key if needed. Explicit environment values override
the file, and saved app settings take precedence for ASR and LLM. Keep all local
configuration and databases private. Distribute the verified build ZIP rather than
re-zipping a directory where Anchor has already run.
