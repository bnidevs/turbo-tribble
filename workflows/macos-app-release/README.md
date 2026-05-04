# Captura — macOS Release Workflow

A GitHub Actions workflow that automatically builds, archives, and publishes a macOS app as a GitHub Release whenever a version tag is pushed.

## What It Does

On every push of a `V*` tag (e.g. `V1.0`, `V2.1.3`), the workflow:

1. Checks out the repo on a macOS runner with Xcode 14.1
2. Strips the Mac Developer code signing identity (CI runners don't have your cert)
3. Builds and archives the Xcode project into an `.xcarchive`
4. Exports the archive to a `.app` bundle using `exopt.plist`
5. Packages the app as both a `.dmg` (via `create-dmg`) and a `.zip`
6. Uploads both artifacts to a GitHub Release for that tag

## Usage

### Trigger a Release

```bash
git tag V1.0.0
git push origin V1.0.0
```

This kicks off the workflow automatically. A GitHub Release will be created with `Captura.dmg` and `Captura.zip` attached.

### Prerequisites

- An `exopt.plist` export options file at the repo root (controls how the `.app` is exported from the archive)
- The Xcode scheme named `"Captura"` and project at `Captura/Captura.xcodeproj`
- `GITHUB_TOKEN` is provided automatically by GitHub Actions — no extra secrets needed

## Files

```
.github/
  workflows/
    releases.yml   # This workflow
exopt.plist        # Xcode export options (required)
Captura/
  Captura.xcodeproj/
```

## Workflow Actions Used

| Action | Version | Notes |
|--------|---------|-------|
| `actions/checkout` | `v6` | Latest |
| `maxim-lobanov/setup-xcode` | `v1` | Pins Xcode to 14.1 — verify latest |
| `softprops/action-gh-release` | `v3` | Node 24 runtime |

## Known Limitations

- **Code signing is stripped** — the exported app will not be notarized or signed. Users on macOS may need to right-click → Open to bypass Gatekeeper.
- **DMG creation uses `continue-on-error: true`** — if `create-dmg` fails silently, the release will be missing the `.dmg` with no pipeline failure. The `.zip` will still be present.
- **Xcode version is hardcoded** to 14.1 — update `xcode-version` in the workflow when bumping Xcode.
