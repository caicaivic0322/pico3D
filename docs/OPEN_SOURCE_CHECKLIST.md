# Open Source Checklist

Use this checklist before publishing the repository or cutting a public release.

## Repository Contents

- `.venv/`, `TRELLIS.2/`, `dist/`, generated model files, generated DMGs, and Hugging Face weights are excluded from git.
- `mac-app/Resources/Backend/` is excluded from git and regenerated during builds by `scripts/stage-backend-resources.sh`.
- The app bundle does not vendor model weights or a Python environment.
- The DMG does not include Python dependencies, Hugging Face model weights, generated outputs, or the upstream `TRELLIS.2` checkout.
- Screenshots and sample input images in `assets/` are safe to redistribute.

## Licenses

- Repository porting code: MIT License.
- TRELLIS.2 upstream code and model: review the upstream MIT license.
- DINOv3 weights: Meta custom license; gated Hugging Face access is required.
- RMBG-2.0 weights: CC BY-NC 4.0; commercial use requires a BRIA license.

## Before Publishing

- Confirm no Hugging Face tokens or API keys are present:

```bash
rg -n "hf_|HUGGINGFACE|token|api_key" . -g '!TRELLIS.2/**' -g '!.venv/**'
```

- Confirm no generated binary artifacts are staged:

```bash
git status --short
```

- Confirm the staged backend bundle is reproducible and only contains allowlisted source/assets:

```bash
bash scripts/stage-backend-resources.sh
```

- Confirm the release build passes:

```bash
bash build-mac-app.sh
bash scripts/package-dmg.sh
bash scripts/verify-release.sh
```

- If publishing a prebuilt DMG for broad download, confirm whether it is ad hoc/local-only or Developer ID signed and notarized. Gatekeeper-ready releases must pass:

```bash
REQUIRE_GATEKEEPER=1 bash scripts/verify-release.sh
```

- Confirm `README.md` explains first-run setup, managed-backend installation, optional repo-folder override for source users, and gated model access.
- Confirm release notes mention that the desktop app is a local shell, not a self-contained model distribution.
- Confirm GitHub issue templates exist for setup failures, generation failures, and release packaging bugs.
