#!/usr/bin/env python3
"""Offline generator for the authoritative GAT1 fixed-point aim table."""

from __future__ import annotations

import argparse
import hashlib
import math
import pathlib
import struct

MAGIC = b"GAT1"
VERSION = 1
ENTRY_COUNT = 4096
QUARTER_COUNT = ENTRY_COUNT // 4
SCALE = 1_000_000
HEADER = struct.Struct("<4sHHI")
ENTRY = struct.Struct("<ii")


def generate_bytes() -> bytes:
    quarter: list[tuple[int, int]] = []
    for offset in range(QUARTER_COUNT):
        angle = (math.pi * 0.5 * offset) / QUARTER_COUNT
        quarter.append((round(math.cos(angle) * SCALE), round(math.sin(angle) * SCALE)))

    entries: list[tuple[int, int]] = []
    for index in range(ENTRY_COUNT):
        quadrant, offset = divmod(index, QUARTER_COUNT)
        x, y = quarter[offset]
        if quadrant == 0:
            direction = (x, y)
        elif quadrant == 1:
            direction = (-y, x)
        elif quadrant == 2:
            direction = (-x, -y)
        else:
            direction = (y, -x)
        entries.append(direction)

    payload = bytearray(HEADER.pack(MAGIC, VERSION, ENTRY_COUNT, SCALE))
    for x, y in entries:
        payload.extend(ENTRY.pack(x, y))
    return bytes(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    data = generate_bytes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"bytes={len(data)} entries={ENTRY_COUNT} sha256={hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
