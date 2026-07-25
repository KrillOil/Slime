"""Normalize Package 2C continuous timing and fallback evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib


def prefixed_json(path: pathlib.Path, prefix: str) -> dict:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return json.loads(line[len(prefix) :])
    raise ValueError(f"{prefix!r} not found in {path}")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def threshold_assessment(result: dict) -> dict:
    simulation = result["stress_simulation_ms"]
    frame = result["whole_frame_ms"]
    return {
        "simulation_p95_le_4ms": simulation["p95"] <= 4.0,
        "simulation_p99_le_6ms": simulation["p99"] <= 6.0,
        "simulation_max_le_8ms": simulation["max"] <= 8.0,
        "whole_frame_p95_le_16_67ms": frame["p95"] <= 16.67,
        "sustained_60_fps": result["measured_fps"] >= 59.9,
        "zero_gameplay_affecting_dropped_ticks":
            result["gameplay_affecting_dropped_ticks"] == 0,
        "zero_replay_divergence": result["replay_divergence_count"] == 0,
        "zero_ledger_error": result["ledger_error_count"] == 0,
        "zero_category_error": result["category_error_count"] == 0,
        "initial_stress_lanes_reached": result["stress_lanes_reached"],
        "preliminary_normal_simulation_p95_le_2ms":
            result["normal_simulation_ms"]["p95"] <= 2.0,
    }


def steady_assessment(result: dict) -> dict:
    history = result["object_history"]
    split = max(1, len(history) // 2)
    early = history[:split]
    late = history[split:]
    constant_fields = ["packets", "drain_records"]
    constants_hold = all(
        len({sample[field] for sample in history}) == 1
        for field in constant_fields
    )
    bounded_fields = ["active", "settled_nonzero"]
    no_growth = all(
        max(sample[field] for sample in late)
        <= max(sample[field] for sample in early)
        for field in bounded_fields
    )
    ticks = [sample["authoritative_tick"] for sample in history]
    return {
        "history_samples": len(history),
        "ticks_strictly_increasing":
            ticks == sorted(set(ticks)) and len(ticks) == len(set(ticks)),
        "constant_owned_object_counts": constants_hold,
        "late_envelope_not_above_early_envelope": no_growth,
        "no_increasing_authoritative_counts_after_transient":
            constants_hold and no_growth,
        "first": history[0],
        "last": history[-1],
    }


def summary(result: dict) -> dict:
    return {
        "timestamp_utc": result["timestamp_utc"],
        "variant": result["variant"],
        "platform": result["platform"],
        "continuous_authority": result["continuous_authority"],
        "measured_seconds": result["measured_seconds"],
        "sample_count": result["sample_count"],
        "measurement_start_tick": result["measurement_start_tick"],
        "maximum_authoritative_tick": result["maximum_authoritative_tick"],
        "measured_authoritative_ticks": result["measured_authoritative_ticks"],
        "stress_simulation_ms": result["stress_simulation_ms"],
        "stress_full_runner_ms": result["stress_full_runner_ms"],
        "stress_checkpoint_hash_ms": result["stress_checkpoint_hash_ms"],
        "normal_simulation_ms_preliminary": result["normal_simulation_ms"],
        "normal_full_runner_ms_preliminary": result["normal_full_runner_ms"],
        "whole_frame_ms": result["whole_frame_ms"],
        "measured_fps": result["measured_fps"],
        "gameplay_affecting_dropped_ticks":
            result["gameplay_affecting_dropped_ticks"],
        "replay_probe_count": result["replay_probe_count"],
        "replay_divergence_count": result["replay_divergence_count"],
        "ledger_error_count": result["ledger_error_count"],
        "category_error_count": result["category_error_count"],
        "stress_lanes": result["stress_lanes"],
        "stress_lanes_reached": result["stress_lanes_reached"],
        "tuning_hash": result["tuning_hash"],
        "room_hash": result["room_hash"],
        "occupancy_hash": result["occupancy_hash"],
        "thresholds": threshold_assessment(result),
        "steady_state": steady_assessment(result),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--canonical-desktop-log", type=pathlib.Path, required=True)
    parser.add_argument("--canonical-web-json", type=pathlib.Path, required=True)
    parser.add_argument("--cell15-desktop-log", type=pathlib.Path, required=True)
    parser.add_argument("--cell15-web-json", type=pathlib.Path, required=True)
    parser.add_argument("--fallback-ladder-json", type=pathlib.Path, required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    canonical_desktop = prefixed_json(
        args.canonical_desktop_log, "P2C_BENCHMARK_RESULT "
    )
    canonical_web = json.loads(args.canonical_web_json.read_text(encoding="utf-8"))
    cell15_desktop = prefixed_json(
        args.cell15_desktop_log, "P2C_BENCHMARK_RESULT "
    )
    cell15_web = json.loads(args.cell15_web_json.read_text(encoding="utf-8"))
    ladder = json.loads(args.fallback_ladder_json.read_text(encoding="utf-8"))
    results = {
        "canonical10_continuous_desktop.json": canonical_desktop,
        "canonical10_continuous_web_chrome.json": canonical_web,
        "cell15_continuous_desktop.json": cell15_desktop,
        "cell15_continuous_web_chrome.json": cell15_web,
        "fallback_ladder.json": ladder,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, result in results.items():
        write_json(args.output_dir / name, result)

    record = {
        "schema": "package-2c-evidence-v2",
        "authoritative": False,
        "excluded_from_state_replay_and_hashes": True,
        "machine": {
            "windows_product": "Windows 10 Pro",
            "windows_display_version": "25H2",
            "windows_build": "26200.8875",
            "cpu": "AMD Ryzen 5 3600 6-Core Processor",
            "ram_bytes": 17129467904,
            "ram_gib": 15.95,
            "gpu": "NVIDIA GeForce GTX 1660 SUPER",
            "gpu_driver_version": "32.0.16.1062",
            "godot": "4.6.3.stable.official.7d41c59c4",
            "chrome_stable": "150.0.7871.184",
        },
        "measurement_contract": {
            "viewport": [960, 540],
            "warmup_seconds": 10,
            "measured_seconds_target": 120,
            "developer_tools_open": False,
            "desktop_export_mode": "debug editor scene",
            "web_export_mode": "Godot Web release",
            "chrome_watchdog_seconds": 170,
            "timing_scopes": {
                "stress_simulation_ms":
                    "GooSimulation.step only; Section 18 thresholds apply here",
                "stress_full_runner_ms":
                    "complete AuthoritativeRunner.step_frame including hash",
                "stress_checkpoint_hash_ms":
                    "canonical validation/serialization/SHA portion",
                "whole_frame_ms": "wall-clock rendered frame",
            },
        },
        "runs": {
            "canonical10_desktop": summary(canonical_desktop),
            "canonical10_web_installed_chrome": summary(canonical_web),
            "cell15_desktop": summary(cell15_desktop),
            "cell15_web_installed_chrome": summary(cell15_web),
        },
        "fallback_ladder": {
            "order": ladder["variant_order"],
            "all_profile_processes_exit_zero":
                all(item["exit_code"] == 0 for item in ladder["commands"]),
            "all_resume_hashes_identical":
                all(item["resume_hash_identical"] for item in ladder["records"]),
            "all_replays_round_trip":
                all(item["replay_round_trip"] for item in ladder["records"]),
            "records": [
                {
                    "variant": item["variant"],
                    "grid_cells": item["grid_cells"],
                    "tuning_hash": item["tuning_hash"],
                    "room_hash": item["room_hash"],
                    "occupancy_hash": item["occupancy_hash"],
                    "replay_sha256": item["replay_sha256"],
                    "core_simulation_us": item["core_simulation_us"],
                    "full_runner_us": item["full_runner_us"],
                    "checkpoint_hash_us": item["checkpoint_hash_us"],
                    "lanes_reached": item["lanes_reached"],
                }
                for item in ladder["records"]
            ],
        },
        "fallback_decision": {
            "thresholds_passed": False,
            "authoritative_tuning_accepted": False,
            "canonical_tuning_retained":
                "f8a3c2e7a071b5b088da2bc1a32edeae7a7fe9dacd7e0d661457603a6f88bc65",
            "reason":
                "Every declared fallback was executed in order in an isolated "
                "project copy with rebuilt tuning, room definition, occupancy, "
                "grid state, and replay bytes. The terminal 15px Web run still "
                "has simulation p95 156.2ms and p99 171.0ms, and its 64x36 grid "
                "can reach only 822 of the permitted minimum 1024 lateral pairs. "
                "It therefore fails timing and declared stress semantics.",
            "terminal_disposition":
                "Stop before G2/production migration and request the Creator's "
                "explicit decision on reduced_basin_column_proposal.md.",
        },
        "original_noncontinuous_evidence_retained": {
            "desktop_raw_sha256": sha256(args.output_dir / "desktop_raw.json"),
            "web_raw_sha256": sha256(args.output_dir / "web_chrome_raw.json"),
            "label":
                "Package 2C first-return reset microbenchmark; non-continuous "
                "and not used for corrected acceptance claims.",
        },
        "deferred_not_mocked": [
            "128 suction jobs",
            "four coverable hazard spans",
            "repeated player immersion transitions",
            "production Rooms 1-4",
        ],
    }
    write_json(args.output_dir / "package_2c_evidence_v2.json", record)
    print(
        "P2C_EVIDENCE_V2 "
        + json.dumps(
            {
                "canonical_web_samples": canonical_web["sample_count"],
                "cell15_web_samples": cell15_web["sample_count"],
                "fallback_variants": len(ladder["records"]),
                "output": str(args.output_dir),
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
