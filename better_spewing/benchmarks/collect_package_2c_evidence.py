"""Normalize non-authoritative Package 2C timing evidence for source control."""

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


def assessment(result: dict) -> dict:
    stress = result["stress_simulation_ms"]
    frame = result["whole_frame_ms"]
    return {
        "stress_p95_le_4ms": stress["p95"] <= 4.0,
        "stress_p99_le_6ms": stress["p99"] <= 6.0,
        "stress_max_le_8ms": stress["max"] <= 8.0,
        "whole_frame_p95_le_16_67ms": frame["p95"] <= 16.67,
        "sustained_60_fps": result["measured_fps"] >= 59.9,
        "zero_gameplay_affecting_dropped_ticks":
            result["gameplay_affecting_dropped_ticks"] == 0,
        "zero_replay_divergence": result["replay_divergence_count"] == 0,
        "zero_ledger_error": result["ledger_error_count"] == 0,
        "zero_category_error": result["category_error_count"] == 0,
        "steady_authoritative_counts": result["steady_counts"]["steady"],
        "stress_lanes_reached": result["stress_lanes_reached"],
        "preliminary_normal_p95_le_2ms":
            result["normal_simulation_ms"]["p95"] <= 2.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--desktop-log", type=pathlib.Path, required=True)
    parser.add_argument("--web-json", type=pathlib.Path, required=True)
    parser.add_argument("--profile-log", type=pathlib.Path, required=True)
    parser.add_argument("--web-pck", type=pathlib.Path, required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    desktop = prefixed_json(args.desktop_log, "P2C_BENCHMARK_RESULT ")
    web = json.loads(args.web_json.read_text(encoding="utf-8"))
    profile = prefixed_json(args.profile_log, "P2C_PROFILE ")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(args.output_dir / "desktop_raw.json", desktop)
    write_json(args.output_dir / "web_chrome_raw.json", web)
    write_json(args.output_dir / "profile_original.json", profile)

    profile_median = profile["median_us"]
    immutable_floor_ms = (
        profile_median["deposition"] + profile_median["state_hash"]
    ) / 1000.0
    record = {
        "schema": "package-2c-evidence-v1",
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
            "desktop_command":
                "Godot_v4.6.3-stable_win64_console.exe --path "
                "\"C:\\Users\\User\\Documents\\Slime Gulper\" "
                "res://better_spewing/benchmarks/flow_benchmark_scene.tscn",
            "web_export_command":
                "Godot_v4.6.3-stable_win64_console.exe --headless --path "
                "\"<independent temporary project copy>\" --export-release Web "
                "\"<temporary project>\\build\\web\\index.html\"",
            "chrome_command":
                "chrome.exe --user-data-dir=<fresh temporary profile> "
                "--no-first-run --no-default-browser-check "
                "--disable-background-timer-throttling "
                "--disable-renderer-backgrounding "
                "--disable-backgrounding-occluded-windows "
                "--window-size=960,540 http://127.0.0.1:8765/index.html",
            "chrome_watchdog_seconds": 170,
            "web_export_pck_bytes": args.web_pck.stat().st_size,
            "web_export_pck_sha256": sha256(args.web_pck),
        },
        "desktop": {
            "timestamp_utc": desktop["timestamp_utc"],
            "measured_seconds": desktop["measured_seconds"],
            "sample_count": desktop["sample_count"],
            "stress_simulation_ms": desktop["stress_simulation_ms"],
            "normal_simulation_ms_preliminary": desktop["normal_simulation_ms"],
            "whole_frame_ms": desktop["whole_frame_ms"],
            "measured_fps": desktop["measured_fps"],
            "maximum_authoritative_tick": desktop["maximum_authoritative_tick"],
            "gameplay_affecting_dropped_ticks":
                desktop["gameplay_affecting_dropped_ticks"],
            "assessment": assessment(desktop),
        },
        "web_installed_stable_chrome": {
            "timestamp_utc": web["timestamp_utc"],
            "measured_seconds": web["measured_seconds"],
            "sample_count": web["sample_count"],
            "stress_simulation_ms": web["stress_simulation_ms"],
            "normal_simulation_ms_preliminary": web["normal_simulation_ms"],
            "whole_frame_ms": web["whole_frame_ms"],
            "measured_fps": web["measured_fps"],
            "maximum_authoritative_tick": web["maximum_authoritative_tick"],
            "gameplay_affecting_dropped_ticks":
                web["gameplay_affecting_dropped_ticks"],
            "assessment": assessment(web),
        },
        "integrity": {
            "desktop_replay_divergence_count":
                desktop["replay_divergence_count"],
            "web_replay_divergence_count": web["replay_divergence_count"],
            "desktop_ledger_error_count": desktop["ledger_error_count"],
            "web_ledger_error_count": web["ledger_error_count"],
            "desktop_category_error_count": desktop["category_error_count"],
            "web_category_error_count": web["category_error_count"],
            "desktop_stress_lanes_reached": desktop["stress_lanes_reached"],
            "web_stress_lanes_reached": web["stress_lanes_reached"],
            "desktop_steady_counts": desktop["steady_counts"],
            "web_steady_counts": web["steady_counts"],
        },
        "profile_original": profile,
        "fallback_decision": {
            "thresholds_passed": False,
            "authoritative_tuning_changed": False,
            "cosmetics":
                "Not applicable to the simulation failure; code-drawn rendering "
                "is required and is outside the timed runner tick.",
            "lateral_pair_reduction":
                "Not applied. The profiled median deposition plus canonical hash "
                f"floor is {immutable_floor_ms:.3f} ms before lateral flow, already "
                "above the 8 ms maximum target.",
            "sleep_aggressiveness":
                "Not applied. The declared saturation state is reconstructed for "
                "each sample, so sleep timing cannot reduce this measured tick.",
            "active_cell_reduction":
                "Not applied. It cannot reduce packet deposition or canonical "
                "hashing, whose measured lower bound already fails.",
            "cell_size_12_or_15":
                "Not applied. The dominant 192-packet Manhattan-radius-4 "
                "deposition search retains the same packet and candidate counts; "
                "even eliminating flow entirely leaves the measured deposition "
                "plus hash floor above target. Rebuilding masks/replays therefore "
                "cannot make this declared workload meet the threshold.",
            "terminal_disposition":
                "Per canonical Section 19.1, stop before production room "
                "migration and return the reduced basin-column model proposal "
                "requirement for Creator approval.",
        },
        "tooling_notes": [
            "Initial export attempt failed because the target directory did not "
            "exist; directory creation made the identical export command pass.",
            "A detached Chrome/server attempt inherited output handles and hung; "
            "one exact orphan Python server was terminated.",
            "The accepted web measurement used one foreground orchestrator with "
            "a 170-second watchdog and exact Chrome process-tree teardown.",
        ],
        "deferred_not_mocked": [
            "128 suction jobs",
            "four coverable hazard spans",
            "repeated player immersion transitions",
            "production Rooms 1-4",
        ],
    }
    write_json(args.output_dir / "package_2c_evidence.json", record)
    print(
        "P2C_EVIDENCE "
        + json.dumps(
            {
                "desktop_samples": desktop["sample_count"],
                "web_samples": web["sample_count"],
                "profile_floor_ms": immutable_floor_ms,
                "output": str(args.output_dir),
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
