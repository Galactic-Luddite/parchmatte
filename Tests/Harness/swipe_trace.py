#!/usr/bin/env python3
"""Analyze an excluded-app swipe trace without claiming unobserved display frames."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCHEMA = "parchmatte.swipe-trace.v1"
BOUNDS_TOLERANCE_PX = 2.0


class TraceError(ValueError):
    pass


@dataclass(frozen=True)
class Cycle:
    number: int
    first_visible_ns: int
    settled_ns: int
    expected_ids: frozenset[int]
    display_bounds: tuple[float, float, float, float]


@dataclass(frozen=True)
class CalibrationEvent:
    video_ns: int
    wall_ns: int


@dataclass(frozen=True)
class Calibration:
    events: tuple[CalibrationEvent, ...]
    video_frame_duration_ns: int
    declared_max_residual_ns: int
    max_total_error_ns: int


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise TraceError(str(error)) from error
    if not lines:
        raise TraceError("trace is empty")
    for line_number, line in enumerate(lines, 1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise TraceError(f"truncated or invalid JSON at line {line_number}: {error.msg}") from error
        if record.get("schema") != SCHEMA:
            raise TraceError(f"wrong schema at line {line_number}")
        records.append(record)
    if records[0].get("type") != "header":
        raise TraceError("first record must be a header")
    return records


def load_correlation(path: Path, header: dict[str, Any]) -> tuple[list[Cycle], Calibration]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if raw.get("schema") != SCHEMA or raw.get("source") != "display-recording-correlation":
        raise TraceError("visual correlation must identify the v1 schema and display-recording source")
    calibration_raw = raw.get("calibration")
    if not isinstance(calibration_raw, dict):
        raise TraceError("visual correlation has no calibration")
    events_raw = calibration_raw.get("events")
    if not isinstance(events_raw, list) or len(events_raw) < 2:
        raise TraceError("calibration requires at least two clock events")
    events = tuple(CalibrationEvent(int(item["videoTimeNS"]), int(item["wallTimeUnixNS"])) for item in events_raw)
    calibration = Calibration(
        events=events,
        video_frame_duration_ns=int(calibration_raw["videoFrameDurationNS"]),
        declared_max_residual_ns=int(calibration_raw["maxResidualNS"]),
        max_total_error_ns=int(calibration_raw["maxTotalErrorNS"]),
    )
    wall_origin = int(header.get("wallTimeUnixNS") or 0)
    monotonic_origin = int(header.get("monotonicOriginNS") or 0)
    cycles = []
    for item in raw.get("cycles", []):
        bounds = item.get("displayBounds", {})
        ids = item.get("expectedCoverIDs", [])
        cycles.append(Cycle(
            number=int(item["cycle"]),
            first_visible_ns=video_to_monotonic(int(item["incomingFirstVisibleVideoNS"]), calibration, wall_origin, monotonic_origin),
            settled_ns=video_to_monotonic(int(item["incomingSettledVideoNS"]), calibration, wall_origin, monotonic_origin),
            expected_ids=frozenset(int(value) for value in ids),
            display_bounds=(float(bounds["x"]), float(bounds["y"]), float(bounds["width"]), float(bounds["height"])),
        ))
    return cycles, calibration


def video_to_wall(video_ns: int, calibration: Calibration) -> int:
    first, last = calibration.events[0], calibration.events[-1]
    if last.video_ns <= first.video_ns or last.wall_ns <= first.wall_ns:
        raise TraceError("calibration events must increase")
    if not first.video_ns <= video_ns <= last.video_ns:
        raise TraceError("video timestamp is outside bracketing calibration events")
    scale = (last.wall_ns - first.wall_ns) / (last.video_ns - first.video_ns)
    return round(first.wall_ns + (video_ns - first.video_ns) * scale)


def video_to_monotonic(video_ns: int, calibration: Calibration, wall_origin: int, monotonic_origin: int) -> int:
    if wall_origin <= 0 or monotonic_origin <= 0:
        raise TraceError("trace header has no wall/monotonic origin anchor")
    return monotonic_origin + video_to_wall(video_ns, calibration) - wall_origin


def intersects(bounds: dict[str, Any], display: tuple[float, float, float, float]) -> bool:
    x, y, width, height = display
    return (
        float(bounds["x"]) < x + width
        and float(bounds["x"]) + float(bounds["width"]) > x
        and float(bounds["y"]) < y + height
        and float(bounds["y"]) + float(bounds["height"]) > y
    )


def valid_bounds(bounds: tuple[float, float, float, float]) -> bool:
    x, y, width, height = bounds
    return (
        all(math.isfinite(value) for value in bounds)
        and abs(x) <= 1_000_000
        and abs(y) <= 1_000_000
        and 0 < width <= 1_000_000
        and 0 < height <= 1_000_000
    )


def cover_has_display_size(bounds: dict[str, Any], display: tuple[float, float, float, float]) -> bool:
    return (
        abs(float(bounds["width"]) - display[2]) <= BOUNDS_TOLERANCE_PX
        and abs(float(bounds["height"]) - display[3]) <= BOUNDS_TOLERANCE_PX
    )


def cover_is_settled(bounds: dict[str, Any], display: tuple[float, float, float, float]) -> bool:
    return all(abs(float(bounds[key]) - expected) <= BOUNDS_TOLERANCE_PX for key, expected in zip(
        ("x", "y", "width", "height"), display
    ))


def valid_cover_candidate(window: dict[str, Any], cycle: Cycle, *, settled: bool = False) -> bool:
    if int(window.get("id", -1)) not in cycle.expected_ids or window.get("owner") != "Parchmatte":
        return False
    bounds = window.get("bounds")
    if not isinstance(bounds, dict):
        raise TraceError("candidate has malformed bounds")
    alpha = window.get("alpha")
    if alpha is None or not math.isfinite(float(alpha)) or not 0 < float(alpha) <= 1:
        return False
    if not intersects(bounds, cycle.display_bounds) or not cover_has_display_size(bounds, cycle.display_bounds):
        return False
    return not settled or cover_is_settled(bounds, cycle.display_bounds)


def validate_calibration(header: dict[str, Any], calibration: Calibration, samples: list[dict[str, Any]], cycles: list[Cycle]) -> list[str]:
    failures: list[str] = []
    events = calibration.events
    if (calibration.video_frame_duration_ns <= 0 or calibration.declared_max_residual_ns < 0
            or calibration.max_total_error_ns <= 0):
        raise TraceError("calibration timing values must be positive")
    if any(right.video_ns <= left.video_ns or right.wall_ns <= left.wall_ns for left, right in zip(events, events[1:])):
        raise TraceError("calibration events must be strictly increasing")
    residuals = [abs(event.wall_ns - video_to_wall(event.video_ns, calibration)) for event in events]
    actual_residual = max(residuals)
    if actual_residual > calibration.declared_max_residual_ns:
        failures.append("calibration residual exceeds declared maximum")
    if calibration.declared_max_residual_ns > calibration.video_frame_duration_ns // 2:
        failures.append("calibration residual budget exceeds half a video frame")
    if calibration.max_total_error_ns > calibration.video_frame_duration_ns:
        failures.append("total correlation error budget exceeds one video frame")
    anchor_uncertainty = int(header.get("anchorUncertaintyNS") or -1)
    if anchor_uncertainty < 0:
        raise TraceError("trace header has no anchor uncertainty")
    timestamps = [int(sample["monotonicNS"]) for sample in samples]
    base_uncertainty = calibration.video_frame_duration_ns // 2 + calibration.declared_max_residual_ns + anchor_uncertainty
    requested = int(header["requestedIntervalNS"])
    for cycle in cycles:
        insertion = next((index for index, value in enumerate(timestamps) if value >= cycle.first_visible_ns), len(timestamps))
        if insertion == 0 or insertion == len(timestamps):
            failures.append(f"cycle {cycle.number}: first-visible time lacks bracketing metadata samples")
            continue
        left, right = timestamps[insertion - 1], timestamps[insertion]
        sampling_ambiguity = (right - left) // 2
        if right - left > requested * 2:
            failures.append(f"cycle {cycle.number}: dropped interval crosses first-visible boundary")
        elif base_uncertainty + sampling_ambiguity > calibration.max_total_error_ns:
            failures.append(f"cycle {cycle.number}: first-visible uncertainty exceeds total error budget")
    return failures


def analyze(records: list[dict[str, Any]], cycles: list[Cycle], required_cycles: int, calibration: Calibration) -> dict[str, Any]:
    if required_cycles <= 0:
        raise TraceError("required cycle count must be positive")
    samples = [record for record in records if record.get("type") == "sample"]
    if not samples:
        raise TraceError("trace has no samples")
    timestamps = [int(sample["monotonicNS"]) for sample in samples]
    if timestamps != sorted(timestamps) or len(set(timestamps)) != len(timestamps):
        raise TraceError("sample timestamps must be strictly increasing")
    requested = int(records[0].get("requestedIntervalNS") or 0)
    if requested <= 0:
        raise TraceError("header has no valid requested interval")
    intervals = [right - left for left, right in zip(timestamps, timestamps[1:])]
    dropped = [value for value in intervals if value > requested * 2]
    duration = timestamps[-1] - timestamps[0]
    sample_rate = (len(samples) - 1) * 1_000_000_000 / duration if duration > 0 else 0.0

    incomplete = validate_calibration(records[0], calibration, samples, cycles)
    sampled_failures: list[str] = []
    if len(cycles) != required_cycles or [cycle.number for cycle in cycles] != list(range(1, required_cycles + 1)):
        incomplete.append(f"incomplete transitions: expected cycles 1..{required_cycles}, got {[cycle.number for cycle in cycles]}")
    previous_settled = -1
    for cycle in cycles:
        if not valid_bounds(cycle.display_bounds):
            incomplete.append(f"cycle {cycle.number}: invalid display bounds")
            continue
        if cycle.first_visible_ns <= previous_settled:
            incomplete.append(f"cycle {cycle.number}: overlapping or out-of-order incoming interval")
        previous_settled = cycle.settled_ns
        if cycle.first_visible_ns >= cycle.settled_ns:
            incomplete.append(f"cycle {cycle.number}: invalid incoming interval")
            continue
        if cycle.first_visible_ns < timestamps[0] or cycle.settled_ns > timestamps[-1]:
            incomplete.append(f"cycle {cycle.number}: trace does not span the full incoming interval")
            continue
        if not cycle.expected_ids:
            incomplete.append(f"cycle {cycle.number}: expected cover IDs are missing")
            continue
        interval_samples = [sample for sample in samples if cycle.first_visible_ns <= int(sample["monotonicNS"]) <= cycle.settled_ns]
        if not interval_samples:
            incomplete.append(f"cycle {cycle.number}: no samples in correlated incoming interval")
            continue
        for sample in interval_samples:
            valid = []
            windows = sample.get("windows")
            if not isinstance(windows, list):
                raise TraceError(f"sample at {sample['monotonicNS']} ns has malformed windows")
            for window in windows:
                if not isinstance(window, dict) or not isinstance(window.get("bounds"), dict):
                    raise TraceError(f"sample at {sample['monotonicNS']} ns has malformed window data")
                if valid_cover_candidate(window, cycle):
                    valid.append(window)
            if not valid:
                sampled_failures.append(
                    f"cycle {cycle.number}: missing, alpha-zero, wrong-ID, or off-display cover at {sample['monotonicNS']} ns"
                )
                break
        settled_sample = min(interval_samples, key=lambda sample: abs(int(sample["monotonicNS"]) - cycle.settled_ns))
        if not any(valid_cover_candidate(window, cycle, settled=True) for window in settled_sample.get("windows", [])):
            sampled_failures.append(f"cycle {cycle.number}: expected cover did not restore to settled display bounds")

    if incomplete:
        status, acceptance, failures = "incomplete", "incomplete", incomplete + sampled_failures
    elif sampled_failures:
        status, acceptance, failures = "sampled-fail", "failed", sampled_failures
    else:
        status, acceptance, failures = "sampled-pass", "incomplete", []

    return {
        "status": status,
        "zeroGapProven": False,
        "issueAcceptance": acceptance,
        "cyclesAnalyzed": len(cycles),
        "samples": len(samples),
        "measuredSampleRateHz": round(sample_rate, 3),
        "medianIntervalMS": round(statistics.median(intervals) / 1_000_000, 3) if intervals else None,
        "droppedIntervals": len(dropped),
        "maxIntervalMS": round(max(intervals) / 1_000_000, 3) if intervals else None,
        "failures": failures,
        "evidenceLimit": "Metadata sampled-pass does not prove any gap-free or frame-by-frame #11 result.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate sampled cover metadata; sampled-pass never proves #11 zero-gap acceptance."
    )
    parser.add_argument("trace", type=Path)
    parser.add_argument("--visual-correlation", type=Path, required=True)
    parser.add_argument("--cycles", type=int, default=10)
    args = parser.parse_args()
    try:
        records = load_jsonl(args.trace)
        cycles, calibration = load_correlation(args.visual_correlation, records[0])
        result = analyze(records, cycles, args.cycles, calibration)
    except (OSError, KeyError, TypeError, ValueError, TraceError) as error:
        result = {
            "status": "incomplete", "zeroGapProven": False,
            "issueAcceptance": "incomplete", "failures": [str(error)],
        }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "sampled-pass" else 1


if __name__ == "__main__":
    sys.exit(main())
