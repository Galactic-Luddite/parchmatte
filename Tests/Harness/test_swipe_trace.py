#!/usr/bin/env python3
"""Regression fixtures for excluded-app swipe trace analysis."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import swipe_trace


def header(interval: int = 8_000_000) -> dict:
    return {
        "schema": swipe_trace.SCHEMA, "type": "header", "monotonicNS": 0,
        "requestedIntervalNS": interval, "wallTimeUnixNS": 1_000_000_000_000,
        "monotonicOriginNS": 1, "anchorUncertaintyNS": 1_000,
    }


def sample(timestamp: int, *, cover_id: int = 41, alpha: float | None = 0.35) -> dict:
    return {
        "schema": swipe_trace.SCHEMA,
        "type": "sample",
        "sequence": timestamp // 8_000_000,
        "monotonicNS": timestamp,
        "windows": [{
            "id": cover_id, "owner": "Parchmatte", "ownerPID": 123, "layer": 1, "alpha": alpha,
            "bounds": {"x": 0, "y": 0, "width": 1440, "height": 900},
        }],
    }


def cycle(number: int, first: int, settled: int, ids: list[int] | None = None) -> swipe_trace.Cycle:
    return swipe_trace.Cycle(number, first, settled, frozenset(ids or [41]), (0, 0, 1440, 900))


def calibration(**changes: int) -> swipe_trace.Calibration:
    values = {
        "video_frame_duration_ns": 16_000_000,
        "declared_max_residual_ns": 1_000_000,
        "max_total_error_ns": 16_000_000,
    }
    values.update(changes)
    return swipe_trace.Calibration(
        events=(
            swipe_trace.CalibrationEvent(0, 1_000_000_000_000),
            swipe_trace.CalibrationEvent(500_000_000, 1_000_500_000_000),
            swipe_trace.CalibrationEvent(1_000_000_000, 1_001_000_000_000),
        ),
        **values,
    )


def analyze(records: list[dict], cycles: list[swipe_trace.Cycle], required: int,
            clock: swipe_trace.Calibration | None = None) -> dict:
    # Normal fixtures include a sample immediately before the correlated edge;
    # boundary-specific regressions call swipe_trace.analyze directly.
    copied = [dict(record) for record in records]
    if cycles and copied[1:] and int(copied[1]["monotonicNS"]) >= cycles[0].first_visible_ns:
        prior = sample(cycles[0].first_visible_ns - 8_000_000)
        copied.insert(1, prior)
    return swipe_trace.analyze(copied, cycles, required, clock or calibration())


class SwipeTraceTest(unittest.TestCase):
    def test_one_pixel_cover_does_not_establish_display_coverage(self) -> None:
        records = [header(), sample(100_000_000), sample(108_000_000)]
        for record in records[1:]:
            record["windows"][0]["bounds"] = {"x": 1439, "y": 0, "width": 1, "height": 900}
        self.assertEqual(analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)["status"], "sampled-fail")

    def test_transition_may_be_offset_but_settled_cover_must_realign(self) -> None:
        records = [header(), sample(100_000_000), sample(108_000_000)]
        records[1]["windows"][0]["bounds"]["x"] = 700
        self.assertEqual(analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)["status"], "sampled-pass")
        records[2]["windows"][0]["bounds"]["x"] = 700
        self.assertEqual(analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)["status"], "sampled-fail")

    def test_calibration_and_boundary_uncertainty_are_enforced(self) -> None:
        records = [header(), sample(92_000_000), sample(100_000_000), sample(108_000_000)]
        target = [cycle(1, 100_000_000, 108_000_000)]
        excessive = calibration(declared_max_residual_ns=9_000_000)
        self.assertEqual(swipe_trace.analyze(records, target, 1, excessive)["status"], "incomplete")
        dropped = [header(), sample(50_000_000), sample(100_000_000), sample(108_000_000)]
        self.assertEqual(swipe_trace.analyze(dropped, target, 1, calibration())["status"], "incomplete")

    def test_result_contract_never_claims_zero_gap(self) -> None:
        passing = analyze(
            [header(), sample(100_000_000), sample(108_000_000)],
            [cycle(1, 100_000_000, 108_000_000)], 1,
        )
        self.assertEqual(
            (passing["status"], passing["zeroGapProven"], passing["issueAcceptance"]),
            ("sampled-pass", False, "incomplete"),
        )
        failing_records = [header(), sample(100_000_000), sample(108_000_000)]
        failing_records[1]["windows"] = []
        failing = analyze(failing_records, [cycle(1, 100_000_000, 108_000_000)], 1)
        self.assertEqual(
            (failing["status"], failing["zeroGapProven"], failing["issueAcceptance"]),
            ("sampled-fail", False, "failed"),
        )
        ambiguous = swipe_trace.analyze(
            [header(), sample(50_000_000), sample(100_000_000), sample(108_000_000)],
            [cycle(1, 100_000_000, 108_000_000)], 1, calibration(),
        )
        self.assertEqual(
            (ambiguous["status"], ambiguous["zeroGapProven"], ambiguous["issueAcceptance"]),
            ("incomplete", False, "incomplete"),
        )

    def test_split_settled_candidates_cannot_combine_into_a_pass(self) -> None:
        records = [header(), sample(100_000_000), sample(108_000_000)]
        records[2]["windows"] = [
            {
                "id": 41, "owner": "Parchmatte", "ownerPID": 123, "layer": 1, "alpha": 0.35,
                "bounds": {"x": 700, "y": 0, "width": 1440, "height": 900},
            },
            {
                "id": 42, "owner": "Parchmatte", "ownerPID": 123, "layer": 1, "alpha": 0.0,
                "bounds": {"x": 0, "y": 0, "width": 1440, "height": 900},
            },
        ]
        result = analyze(records, [cycle(1, 100_000_000, 108_000_000, [41, 42])], 1)
        self.assertEqual(result["status"], "sampled-fail")

    def test_missing_or_out_of_range_calibration_is_incomplete(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "correlation.json"
            path.write_text(json.dumps({"schema": swipe_trace.SCHEMA, "source": "display-recording-correlation", "cycles": []}))
            with self.assertRaisesRegex(swipe_trace.TraceError, "no calibration"):
                swipe_trace.load_correlation(path, header())
            correlation = {
                "schema": swipe_trace.SCHEMA, "source": "display-recording-correlation",
                "calibration": {
                    "videoFrameDurationNS": 16_000_000, "maxResidualNS": 1_000_000,
                    "maxTotalErrorNS": 16_000_000,
                    "events": [
                        {"videoTimeNS": 100, "wallTimeUnixNS": 1_000_000_000_000},
                        {"videoTimeNS": 200, "wallTimeUnixNS": 1_000_000_000_100},
                    ],
                },
                "cycles": [{
                    "cycle": 1, "incomingFirstVisibleVideoNS": 50, "incomingSettledVideoNS": 150,
                    "expectedCoverIDs": [41], "displayBounds": {"x": 0, "y": 0, "width": 1440, "height": 900},
                }],
            }
            path.write_text(json.dumps(correlation))
            with self.assertRaisesRegex(swipe_trace.TraceError, "outside bracketing"):
                swipe_trace.load_correlation(path, header())

    def test_invalid_display_bounds_fail(self) -> None:
        for bounds in ((0, 0, 0, 900), (0, 0, float("nan"), 900), (2_000_000, 0, 1440, 900)):
            with self.subTest(bounds=bounds):
                bad_cycle = swipe_trace.Cycle(1, 100_000_000, 108_000_000, frozenset([41]), bounds)
                result = analyze(
                    [header(), sample(100_000_000), sample(108_000_000)], [bad_cycle], 1,
                )
                self.assertEqual(result["status"], "incomplete")

    def test_malformed_window_data_is_incomplete(self) -> None:
        records = [header(), sample(100_000_000), sample(108_000_000)]
        records[0]["monotonicOriginNS"] = 100_000_000
        records[1]["windows"] = [{"id": 41, "owner": "Parchmatte"}]
        with self.assertRaisesRegex(swipe_trace.TraceError, "malformed window data"):
            analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)

    def test_trace_must_span_full_correlated_interval(self) -> None:
        for first, settled in ((90_000_000, 108_000_000), (100_000_000, 120_000_000)):
            result = analyze(
                [header(), sample(100_000_000), sample(108_000_000)],
                [cycle(1, first, settled)], 1,
            )
            self.assertEqual(result["status"], "incomplete")

    def test_repeated_interval_cannot_count_as_two_cycles(self) -> None:
        result = analyze(
            [header(), sample(100_000_000), sample(108_000_000)],
            [cycle(1, 100_000_000, 108_000_000), cycle(2, 100_000_000, 108_000_000)], 2,
        )
        self.assertEqual(result["status"], "incomplete")

    def test_nonfinite_or_out_of_range_alpha_fails(self) -> None:
        for alpha in (float("nan"), float("inf"), 1.1):
            result = analyze(
                [header(), sample(100_000_000, alpha=alpha), sample(108_000_000)],
                [cycle(1, 100_000_000, 108_000_000)], 1,
            )
            self.assertEqual(result["status"], "sampled-fail")

    def test_zero_required_cycles_is_invalid(self) -> None:
        with self.assertRaises(swipe_trace.TraceError):
            analyze([header(), sample(100_000_000)], [], 0)

    def test_passes_ten_correlated_departure_return_cycles(self) -> None:
        records = [header()]
        cycles = []
        for number in range(1, 11):
            first = number * 100_000_000
            settled = first + 16_000_000
            # The deliberately unpapered excluded outgoing portion precedes first.
            records.extend([sample(first - 8_000_000), sample(first), sample(first + 8_000_000), sample(settled)])
            cycles.append(cycle(number, first, settled))
        result = analyze(records, cycles, 10)
        self.assertEqual(result["status"], "sampled-pass", result)

    def test_missing_cover_fails(self) -> None:
        records = [header(), sample(100_000_000), sample(108_000_000)]
        records[2]["windows"] = []
        result = analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)
        self.assertEqual(result["status"], "sampled-fail")

    def test_alpha_zero_and_missing_alpha_fail(self) -> None:
        for alpha in (0.0, None):
            with self.subTest(alpha=alpha):
                result = analyze(
                    [header(), sample(100_000_000, alpha=alpha), sample(108_000_000)],
                    [cycle(1, 100_000_000, 108_000_000)], 1,
                )
                self.assertEqual(result["status"], "sampled-fail")

    def test_wrong_cover_id_fails(self) -> None:
        result = analyze(
            [header(), sample(100_000_000, cover_id=99), sample(108_000_000, cover_id=99)],
            [cycle(1, 100_000_000, 108_000_000, [41])], 1,
        )
        self.assertEqual(result["status"], "sampled-fail")

    def test_incomplete_transitions_fail(self) -> None:
        result = analyze(
            [header(), sample(100_000_000), sample(108_000_000)],
            [cycle(2, 100_000_000, 108_000_000)], 2,
        )
        self.assertIn("incomplete transitions", result["failures"][0])
        self.assertEqual(result["status"], "incomplete")

    def test_excluded_outgoing_region_is_not_evaluated(self) -> None:
        records = [header(), sample(80_000_000), sample(92_000_000), sample(100_000_000), sample(108_000_000)]
        records[1]["windows"] = []
        records[2]["windows"] = []
        result = analyze(records, [cycle(1, 100_000_000, 108_000_000)], 1)
        self.assertEqual(result["status"], "sampled-pass", result)
        self.assertFalse(result["zeroGapProven"])
        self.assertEqual(result["issueAcceptance"], "incomplete")

    def test_empty_and_truncated_trace_are_incomplete(self) -> None:
        for content in ("", json.dumps(header()) + "\n{"):
            with self.subTest(content=content):
                with tempfile.TemporaryDirectory() as raw:
                    path = Path(raw) / "trace.jsonl"
                    path.write_text(content, encoding="utf-8")
                    with self.assertRaises(swipe_trace.TraceError):
                        swipe_trace.load_jsonl(path)

    def test_reports_dropped_intervals(self) -> None:
        result = analyze(
            [header(), sample(100_000_000), sample(140_000_000)],
            [cycle(1, 100_000_000, 140_000_000)], 1,
        )
        self.assertEqual(result["droppedIntervals"], 1)


if __name__ == "__main__":
    unittest.main()
