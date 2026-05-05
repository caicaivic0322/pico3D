# Release Process

This repository ships TrellisMac as a lightweight Apple Silicon desktop shell around the local Python TRELLIS workflow. The app bundle is built for arm64 and expects the Python environment, upstream checkout, model weights, and user outputs to stay outside the app.

## Build Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Xcode or Command Line Tools for `swiftc`, `codesign`, `hdiutil`, and `lipo`
- Python 3.11 for the backend setup workflow

## Version Source

Release scripts read `CFBundleShortVersionString` from `mac-app/Info.plist`. The DMG name uses this format:

```text
TrellisMac-<CFBundleShortVersionString>-arm64.dmg
```

Update both `CFBundleShortVersionString` and `CFBundleVersion` before publishing a new release.

## Build App

```bash
bash build-mac-app.sh
```

The app bundle is written to:

```text
dist/TrellisMac.app
```

The build script compiles the SwiftUI app as `arm64-apple-macos13.0`, copies `mac-app/Info.plist` and `mac-app/Resources`, stages the redistributable backend source via `scripts/stage-backend-resources.sh`, checks that the executable contains `arm64`, and signs the bundle. By default it uses ad hoc signing with `SIGN_IDENTITY=-`; that is suitable for local/open-source builds but is not a Gatekeeper-accepted public binary.

`mac-app/Resources/Backend/` is treated as a build-time generated directory and is intentionally excluded from git. Update `scripts/stage-backend-resources.sh` when the bundled backend file set changes.

## Build DMG

```bash
bash scripts/package-dmg.sh
```

The DMG and checksum are written to:

```text
dist/TrellisMac-0.1.0-arm64.dmg
dist/TrellisMac-0.1.0-arm64.dmg.sha256
```

The checksum file is generated from inside `dist`, so it is portable:

```bash
cd dist
shasum -a 256 -c TrellisMac-0.1.0-arm64.dmg.sha256
```

The DMG contains `TrellisMac.app` as the application payload, plus a small first-run note and an `/Applications` shortcut. It does not include Python dependencies, Hugging Face model weights, the `TRELLIS.2` checkout, or generated outputs.

On first launch, `TrellisMac.app` installs the staged backend bundle into `~/Library/Application Support/TrellisMac/Backend`. End users can start from the DMG alone; they do not need a separate clone of this repository unless they want to modify the source. `setup.sh` then creates `.venv`, installs Python dependencies, clones `TRELLIS.2`, and applies the Apple Silicon patches inside that managed backend directory.

## Verify Release

```bash
bash build-mac-app.sh
bash scripts/package-dmg.sh
bash scripts/verify-release.sh
```

`scripts/verify-release.sh` checks the source plist, the built app bundle, the staged backend-backed resource layout, the app executable, the code signature, the DMG checksum, DMG mountability, and the expected files in the mounted DMG. By default it accepts ad hoc local builds. For a Developer ID signed and notarized public DMG, run it with `REQUIRE_GATEKEEPER=1`.

## Optional Developer ID Signing

Ad hoc signing is enough for local development:

```bash
bash build-mac-app.sh
```

This default DMG is ad hoc signed and intended for local testing or source users who understand macOS Gatekeeper warnings. Do not label it as a Gatekeeper-ready public binary unless the Developer ID signing and notarization flow below passes.

For a public binary signed with a paid Apple Developer ID certificate, set `SIGN_IDENTITY` to the exact certificate name from `security find-identity -v -p codesigning`:

```bash
SIGN_IDENTITY="$SIGN_IDENTITY" bash build-mac-app.sh
bash scripts/package-dmg.sh
REQUIRE_GATEKEEPER=1 bash scripts/verify-release.sh
```

Notarization requires Apple credentials configured outside this repository. Set `NOTARY_PROFILE` to your local `notarytool` keychain profile, submit the generated DMG, then staple the ticket:

```bash
NOTARY_PROFILE="$NOTARY_PROFILE"
xcrun notarytool submit dist/TrellisMac-0.1.0-arm64.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/TrellisMac-0.1.0-arm64.dmg
spctl -a -vv -t open --context context:primary-signature dist/TrellisMac-0.1.0-arm64.dmg
(
    cd dist
    shasum -a 256 TrellisMac-0.1.0-arm64.dmg > TrellisMac-0.1.0-arm64.dmg.sha256
)
bash scripts/verify-release.sh
REQUIRE_GATEKEEPER=1 bash scripts/verify-release.sh
```

## Release Checklist

- Update `CFBundleShortVersionString` and `CFBundleVersion` in `mac-app/Info.plist`.
- Run `bash build-mac-app.sh`.
- Run `bash scripts/package-dmg.sh`.
- Run `bash scripts/verify-release.sh`.
- For a signed public binary, run `REQUIRE_GATEKEEPER=1 bash scripts/verify-release.sh` after notarization and stapling.
- Create a git tag such as `v0.1.0`.
- Upload the DMG and `.sha256` file to the GitHub release.
- Include license caveats for TRELLIS.2, DINOv3, and RMBG-2.0 in the release notes.

For a source-plus-DMG GitHub release, also include:

- A short "What This DMG Contains" section explaining that the app manages its own backend on first launch but still downloads Python dependencies and model weights locally.
- A short "First Launch" section covering setup, Hugging Face access, login, and the first-run model download.
- A note that ad hoc builds may trigger Gatekeeper warnings unless the release is Developer ID signed and notarized.

You can start from `docs/GITHUB_RELEASE_TEMPLATE.md` when drafting the GitHub release body.
