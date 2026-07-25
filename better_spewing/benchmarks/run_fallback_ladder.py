"""Profile every cumulative Section 19.1 fallback in isolated project copies."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

VARIANTS = [
    "canonical10",
    "cosmetics",
    "lateral1024",
    "sleep6",
    "active1024",
    "cell12",
    "cell15",
]


def copy_project(source: pathlib.Path, root: pathlib.Path, variant: str) -> pathlib.Path:
    destination = pathlib.Path(tempfile.mkdtemp(prefix=f"{variant}-", dir=root))
    ignored = shutil.ignore_patterns(
        ".git", ".godot", ".godot-user", "build", "captures", "__pycache__"
    )
    shutil.copytree(source, destination, dirs_exist_ok=True, ignore=ignored)
    return destination


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"expected exactly one tuning occurrence: {old}")
    return text.replace(old, new)


def patch_variant(project: pathlib.Path, variant: str) -> None:
    step = VARIANTS.index(variant)
    tuning_path = project / "better_spewing" / "contracts" / "goo_tuning.gd"
    text = tuning_path.read_text(encoding="utf-8")
    if step >= VARIANTS.index("lateral1024"):
        text = replace_once(
            text,
            '"maximum_lateral_pairs_per_tick": 2048,',
            '"maximum_lateral_pairs_per_tick": 1024,',
        )
    if step >= VARIANTS.index("sleep6"):
        text = replace_once(
            text,
            '"sleep_threshold_processed_ticks": 12,',
            '"sleep_threshold_processed_ticks": 6,',
        )
    if step >= VARIANTS.index("active1024"):
        text = replace_once(
            text,
            '"maximum_active_cells_per_tick": 1536,',
            '"maximum_active_cells_per_tick": 1024,',
        )
    if step >= VARIANTS.index("cell12"):
        text = replace_once(
            text, '"grid_cell_size_px": 10,', '"grid_cell_size_px": 12,'
        )
        text = replace_once(
            text, '"grid_width_cells": 96,', '"grid_width_cells": 80,'
        )
        text = replace_once(
            text, '"grid_height_cells": 54,', '"grid_height_cells": 45,'
        )
    if step >= VARIANTS.index("cell15"):
        text = replace_once(
            text, '"grid_cell_size_px": 12,', '"grid_cell_size_px": 15,'
        )
        text = replace_once(
            text, '"grid_width_cells": 80,', '"grid_width_cells": 64,'
        )
        text = replace_once(
            text, '"grid_height_cells": 45,', '"grid_height_cells": 36,'
        )
    tuning_path.write_text(text, encoding="utf-8")


def parse_result(stdout: str) -> dict:
    prefix = "P2C_VARIANT_PROFILE "
    for line in stdout.splitlines():
        if line.startswith(prefix):
            return json.loads(line[len(prefix) :])
    raise RuntimeError("Godot profile produced no variant result")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=pathlib.Path, required=True)
    parser.add_argument("--godot", type=pathlib.Path, required=True)
    parser.add_argument("--working-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.working_root.mkdir(parents=True, exist_ok=True)
    records = []
    commands = []
    for variant in VARIANTS:
        project = copy_project(args.project, args.working_root, variant)
        patch_variant(project, variant)
        log_dir = project / ".godot-user"
        log_dir.mkdir(parents=True, exist_ok=True)
        command = [
            str(args.godot),
            "--headless",
            "--log-file",
            str(log_dir / "variant-profile.log"),
            "--path",
            str(project),
            "-s",
            "res://better_spewing/benchmarks/profile_variant.gd",
        ]
        environment = os.environ.copy()
        environment["P2C_VARIANT"] = variant
        completed = subprocess.run(
            command,
            env=environment,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
            check=False,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"{variant} profile failed with {completed.returncode}\n"
                f"{completed.stdout}"
            )
        records.append(parse_result(completed.stdout))
        commands.append({"variant": variant, "command": command, "exit_code": 0})
        print(f"P2C_FALLBACK_VARIANT {variant} PASS", flush=True)
    result = {
        "schema": "package-2c-fallback-ladder-v1",
        "authoritative": False,
        "variant_order": VARIANTS,
        "commands": commands,
        "records": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("P2C_FALLBACK_LADDER " + json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
