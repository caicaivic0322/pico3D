# Mesh Regression Baseline

Use this workflow when comparing geometry quality changes in `backends/mesh_extract.py` or `generate.py`.

## Default Baseline

The baseline runner uses a fixed default image and fixed default parameters:

- Image: `assets/shoe_input.png`
- Stage: `geometry`
- Pipeline: `1024_cascade`
- Seed: `42`
- Texture size: `1024`
- Simplify target faces: `0`

Run:

```bash
bash scripts/run-mesh-regression-baseline.sh
```

Outputs are written under:

```text
baseline-results/<timestamp>/
```

Each run produces:

- `run.log`: full console log from `generate.py`
- `metrics.json`: parsed structured metrics for comparison
- `baseline.obj` / `baseline.glb` / `baseline.trellis_state.pt`: generated stage outputs

## Override The Image

To compare a problem case such as a specific vehicle image, pass the image path explicitly while keeping the same default parameters:

```bash
bash scripts/run-mesh-regression-baseline.sh /absolute/path/to/problem-image.png
```

## Key Metrics To Track

- `mesh_extract.output.triangles`
- `mesh_extract.output.unique_triangles`
- `mesh_extract.output.duplicate_triangle_ratio`
- `stages.generation_mesh.components`
- `stages.export_source_mesh.components`
- `stages.geometry_export_mesh.components`
- `stages.*.largest_ratio_percent`

When comparing two runs after code changes, look for:

- fewer duplicate quads/triangles
- lower duplicate triangle ratio
- fewer connected components
- higher largest component ratio
- fewer faces removed during repair/cleanup for the same input
