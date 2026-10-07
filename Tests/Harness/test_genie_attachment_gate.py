import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from genie_attachment_gate import assess


class AttachmentGateTests(unittest.TestCase):
    def frame(self, t, outside=0, alpha=0.6):
        return {"t": t, "alpha": alpha, "outside": outside}

    def test_consecutive_visible_spill_rejects_candidate(self):
        result = assess([self.frame(0, 2), self.frame(1 / 60, 3)])
        self.assertEqual(result["verdict"], "REJECTED")
        self.assertEqual(result["consecutive_spill_pairs"], 1)

    def test_clear_vertices_do_not_prove_full_surface_attachment(self):
        self.assertEqual(assess([self.frame(0), self.frame(1 / 60)])["verdict"],
                         "INCONCLUSIVE")

    def test_inconclusive_cli_cannot_be_mistaken_for_shell_success(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / "frames.json"
            data.write_text(json.dumps([self.frame(0), self.frame(1 / 60)]))
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("genie_attachment_gate.py")),
                 str(data)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(result.stdout)["verdict"], "INCONCLUSIVE")

    def test_single_spill_reports_without_promoting_or_rejecting(self):
        result = assess([self.frame(0, 1)])
        self.assertEqual(result["verdict"], "INCONCLUSIVE")
        self.assertEqual(result["visible_spill_frames"], 1)
        self.assertEqual(result["consecutive_spill_pairs"], 0)

    def test_consecutive_boundary_is_inclusive(self):
        for gap, pairs in ((0.0334, 1), (0.033401, 0)):
            with self.subTest(gap=gap):
                self.assertEqual(assess([self.frame(0, 1), self.frame(gap, 1)])[
                    "consecutive_spill_pairs"], pairs)

    def test_separate_motion_segments_do_not_form_consecutive_failure(self):
        result = assess([self.frame(0, 1), self.frame(4, 1)])
        self.assertEqual(result["consecutive_spill_pairs"], 0)

    def test_invisible_endpoint_does_not_count_as_visible_ghost(self):
        result = assess([self.frame(0, 209, 0), self.frame(1 / 60, 209, 0)])
        self.assertEqual(result["consecutive_spill_pairs"], 0)

    def test_missing_or_invalid_observations_are_not_a_geometry_verdict(self):
        for frames in ([], [self.frame(float("nan"))],
                       [self.frame(1), self.frame(0)],
                       [self.frame(0, -1)], [self.frame(0, 1, 0.7)]):
            with self.subTest(frames=frames):
                with self.assertRaises(ValueError):
                    assess(frames)


if __name__ == "__main__":
    unittest.main()
