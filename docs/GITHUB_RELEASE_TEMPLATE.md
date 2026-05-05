# GitHub Release Template

Use this as the starting point for a public source-plus-DMG release.

## Summary

TrellisMac packages the Apple Silicon TRELLIS workflow in a lightweight macOS desktop shell.

- Download the DMG to use the desktop app.
- Clone the repository if you want to inspect or modify the source.
- The app is not a self-contained model distribution: first launch still installs Python dependencies, clones `TRELLIS.2`, and downloads Hugging Face model weights locally.

## Downloads

- `TrellisMac-<version>-arm64.dmg`
- `TrellisMac-<version>-arm64.dmg.sha256`

Verify the checksum:

```bash
shasum -a 256 -c TrellisMac-<version>-arm64.dmg.sha256
```

## What This DMG Contains

- `TrellisMac.app`
- A staged copy of the redistributable backend source used to bootstrap first launch
- No Python environment, model weights, `TRELLIS.2` checkout, or generated outputs

## First Launch

1. Open `TrellisMac.app`.
2. Run the in-app first-run steps to install the managed backend and environment.
3. Request access to the gated Hugging Face models.
4. Log in with `huggingface-cli`.
5. Wait for the first-time dependency, upstream checkout, and model downloads to finish.

## Notes

- This release is `ad-hoc` signed unless stated otherwise, so Gatekeeper may require a manual confirmation on first open.
- DINOv3 and RMBG-2.0 model access and license terms still apply.
- `RMBG-2.0` is non-commercial unless separately licensed by BRIA.
