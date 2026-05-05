#!/usr/bin/env python3

import argparse
import json
import os
import re
from typing import Any


def parse_int(text: str) -> int:
    return int(text.replace(",", ""))


def parse_float(text: str) -> float:
    return float(text.replace(",", ""))


def stage_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


def ensure_stage(metrics: dict[str, Any], name: str) -> dict[str, Any]:
    key = stage_key(name)
    return metrics.setdefault("stages", {}).setdefault(key, {"label": name})


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract structured mesh regression metrics from a generate.py log.")
    parser.add_argument("log_path", help="Path to captured generate.py stdout/stderr log")
    parser.add_argument("--output", help="Optional JSON output path")
    args = parser.parse_args()

    with open(args.log_path, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]

    metrics: dict[str, Any] = {
        "version": 1,
        "log_path": os.path.abspath(args.log_path),
        "config": {},
        "timings": {},
        "mesh_extract": {},
        "stages": {},
        "files": {},
    }

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        if stripped.startswith("Stage: "):
            metrics["config"]["stage"] = stripped.split(": ", 1)[1]
            continue

        match = re.match(r"^Input: (.+) \((\d+)x(\d+)\)$", stripped)
        if match:
            metrics["config"]["image_path"] = match.group(1)
            metrics["config"]["image_width"] = int(match.group(2))
            metrics["config"]["image_height"] = int(match.group(3))
            continue

        match = re.match(r"^Generating (?:OBJ geometry|3D model) \(pipeline=([^,]+), seed=(\d+)\)\.\.\.$", stripped)
        if match:
            metrics["config"]["pipeline_type"] = match.group(1)
            metrics["config"]["seed"] = int(match.group(2))
            continue

        match = re.match(r"^Texture baker backend: (.+)$", stripped)
        if match:
            metrics["config"]["texture_backend"] = match.group(1)
            continue

        match = re.match(r"^Mesh: ([\d,]+) vertices, ([\d,]+) triangles$", stripped)
        if match:
            metrics["stages"]["raw_generation_mesh"] = {
                "label": "Raw generation mesh",
                "vertices": parse_int(match.group(1)),
                "triangles": parse_int(match.group(2)),
            }
            continue

        match = re.match(r"^Generation time: ([\d.]+)s$", stripped)
        if match:
            metrics["timings"]["generation_seconds"] = parse_float(match.group(1))
            continue

        match = re.match(
            r"^\[mesh-debug\] input: voxels=(\d+), dual_vertices=\((\d+),\s*(\d+)\), "
            r"intersections_xyz=\[(\d+), (\d+), (\d+)\], grid_size=\[(\d+), (\d+), (\d+)\]$",
            stripped,
        )
        if match:
            metrics["mesh_extract"]["input"] = {
                "voxels": int(match.group(1)),
                "dual_vertices_shape": [int(match.group(2)), int(match.group(3))],
                "intersections_xyz": [int(match.group(4)), int(match.group(5)), int(match.group(6))],
                "grid_size": [int(match.group(7)), int(match.group(8)), int(match.group(9))],
            }
            continue

        match = re.match(r"^\[mesh-debug\] candidate_quads=(\d+)$", stripped)
        if match:
            metrics["mesh_extract"]["candidate_quads"] = int(match.group(1))
            continue

        match = re.match(r"^\[mesh-debug\] valid_quads=(\d+), dropped_quads=(\d+), valid_ratio=([\d.]+)%$", stripped)
        if match:
            metrics["mesh_extract"]["valid_quads"] = int(match.group(1))
            metrics["mesh_extract"]["dropped_quads"] = int(match.group(2))
            metrics["mesh_extract"]["valid_ratio_percent"] = parse_float(match.group(3))
            continue

        for key, pattern in [
            ("dropped_degenerate_quads", r"^\[mesh-debug\] dropped_degenerate_quads=(\d+)$"),
            ("removed_duplicate_quads", r"^\[mesh-debug\] removed_duplicate_quads=(\d+)$"),
            ("dropped_degenerate_triangles", r"^\[mesh-debug\] dropped_degenerate_triangles=(\d+)$"),
            ("removed_duplicate_triangles", r"^\[mesh-debug\] removed_duplicate_triangles=(\d+)$"),
        ]:
            match = re.match(pattern, stripped)
            if match:
                metrics["mesh_extract"][key] = int(match.group(1))
                break
        else:
            match = re.match(
                r"^\[mesh-debug\] output: vertices=(\d+), triangles=(\d+), unique_triangles=(\d+), used_vertices=(\d+)$",
                stripped,
            )
            if match:
                triangles = int(match.group(2))
                unique_triangles = int(match.group(3))
                metrics["mesh_extract"]["output"] = {
                    "vertices": int(match.group(1)),
                    "triangles": triangles,
                    "unique_triangles": unique_triangles,
                    "used_vertices": int(match.group(4)),
                    "duplicate_triangle_ratio": 0.0 if triangles == 0 else 1.0 - (unique_triangles / triangles),
                }
                continue

            match = re.match(
                r"^(.*) connected components: ([\d,]+), largest=([\d,]+) faces \(([\d.]+)%\)$",
                stripped,
            )
            if match:
                stage = ensure_stage(metrics, match.group(1))
                stage["components"] = parse_int(match.group(2))
                stage["largest_faces"] = parse_int(match.group(3))
                stage["largest_ratio_percent"] = parse_float(match.group(4))
                continue

            match = re.match(
                r"^(.*): removed ([\d,]+) tiny fragments \(< ([\d,]+) faces\); retained ([\d,]+)/([\d,]+) faces$",
                stripped,
            )
            if match:
                stage = ensure_stage(metrics, match.group(1))
                stage["removed_tiny_fragments"] = parse_int(match.group(2))
                stage["tiny_fragment_min_faces"] = parse_int(match.group(3))
                stage["retained_faces"] = parse_int(match.group(4))
                stage["total_faces_before_fragment_prune"] = parse_int(match.group(5))
                continue

            match = re.match(
                r"^(.*): keeping largest connected component \(([\d,]+)/([\d,]+) faces, ([\d.]+)%\)$",
                stripped,
            )
            if match:
                stage = ensure_stage(metrics, match.group(1))
                stage["largest_component_faces"] = parse_int(match.group(2))
                stage["total_component_faces"] = parse_int(match.group(3))
                stage["largest_component_ratio_percent"] = parse_float(match.group(4))
                continue

            match = re.match(r"^(.*): repaired mesh geometry \(([\d,]+) -> ([\d,]+) faces\)$", stripped)
            if match:
                stage = ensure_stage(metrics, match.group(1))
                stage["repair_faces_before"] = parse_int(match.group(2))
                stage["repair_faces_after"] = parse_int(match.group(3))
                continue

            match = re.match(r"^Simplifying mesh: ([\d,]+) -> ~([\d,]+) faces$", stripped)
            if match:
                metrics["timings"]["simplify_requested_from_faces"] = parse_int(match.group(1))
                metrics["timings"]["simplify_target_faces"] = parse_int(match.group(2))
                continue

            match = re.match(r"^Saved (.+): (.+)$", stripped)
            if match:
                label = stage_key(match.group(1))
                metrics["files"][label] = match.group(2)
                continue

            match = re.match(r"^Saved bake state: (.+)$", stripped)
            if match:
                metrics["files"]["bake_state"] = match.group(1)
                continue

            match = re.match(r"^Total time: ([\d.]+)s generation(?: \+ baking)?$", stripped)
            if match:
                metrics["timings"]["total_seconds"] = parse_float(match.group(1))
                continue

            match = re.match(r"^Texture stage time: ([\d.]+)s$", stripped)
            if match:
                metrics["timings"]["texture_stage_seconds"] = parse_float(match.group(1))
                continue

            match = re.match(r"^Bake time: ([\d.]+)s$", stripped)
            if match:
                metrics["timings"]["bake_seconds"] = parse_float(match.group(1))
                continue

    output_text = json.dumps(metrics, indent=2, sort_keys=True)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_text)
            f.write("\n")
    else:
        print(output_text)


if __name__ == "__main__":
    main()
