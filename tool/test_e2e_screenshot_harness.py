"""Offline tests of the live screenshot harness. No UI or devices are driven."""
import argparse
import struct
import zlib
import importlib.util
import json
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).with_name("e2e_screenshot_harness.py")
spec = importlib.util.spec_from_file_location("e2e_screenshot_harness", SOURCE)
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

def png_chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


PNG = (h.PNG_MAGIC
       + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
       + png_chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff"))
       + png_chunk(b"IEND", b""))


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cfg = dict(
            session="test-session", host=socket.gethostname(), platform="linux", app_version="0.8.0+8",
            build_id="sha256:dummy", source_revision="abc123",
            wayland_display="wayland-test", runtime_dir="/run/user/1000"
        )
        (self.root / "session.json").write_text(json.dumps(self.cfg))

    def capture(self, flow="setup", action="Open Home", kind="screen-open"):
        args = argparse.Namespace(
            flow=flow, kind=kind, action=action, expected="Home",
            settle_ms=0,
        )
        with patch.object(h, "take_png", return_value=PNG):
            h.capture(self.root, self.cfg, args, None)

    def review(self, row):
        h.cmd_review(argparse.Namespace(
            root=self.root, id=row, actual="Home shown", verdict="PASS",
            critique="Readable layout, contrast, typography, and alignment",
            severity="none", retest_id=None,
        ))

    def test_unique_names_metadata_review_and_completed_flow(self):
        self.capture()
        self.capture(action="Focus next control", kind="action")
        rows, _ = h.effective(self.root)
        self.assertEqual([x["id"] for x in rows], [1, 2])
        self.assertNotEqual(rows[0]["screenshot"], rows[1]["screenshot"])
        for row in rows:
            self.assertEqual(row["host"], self.cfg["host"])
            self.assertEqual(row["build_id"], "sha256:dummy")
            self.assertEqual((row["width"], row["height"]), (1, 1))
            self.assertIn("captured_at_nz", row)
            self.assertTrue((self.root / row["screenshot"]).is_file())
            self.review(row["id"])
        h.cmd_complete(argparse.Namespace(
            root=self.root, flow="setup", status="PASS",
            notes="Captured and reviewed two UI states",
        ))
        h.cmd_verify(argparse.Namespace(root=self.root, require_flows=1))
        h.cmd_report(argparse.Namespace(root=self.root))
        markdown = (self.root / "SCREENSHOT-MANIFEST.md").read_text()
        self.assertIn("Readable layout", markdown)
        self.assertIn("[PNG]", markdown)

    def test_unreviewed_cannot_complete_or_verify(self):
        self.capture()
        with self.assertRaises(SystemExit):
            h.cmd_complete(argparse.Namespace(
                root=self.root, flow="setup", status="PASS", notes="no"
            ))
        with self.assertRaises(SystemExit):
            h.cmd_verify(argparse.Namespace(root=self.root, require_flows=0))

    def test_refuses_physical_android(self):
        cfg = dict(self.cfg, platform="waydroid", adb_serial="10.66.66.3:5555")
        with patch.object(h, "run", return_value=b"SM_S931B"):
            with self.assertRaises(SystemExit) as ctx:
                h.waydroid(cfg)
        self.assertIn("non-Waydroid", str(ctx.exception))

    def test_android_launch_uses_explicit_activity_not_monkey(self):
        cfg = dict(self.cfg, platform="waydroid", adb_serial="192.168.240.112:5555")
        args = argparse.Namespace(
            input="launch", key=None, text=None, x=None, y=None,
            end_x=None, end_y=None, duration_ms=300,
        )
        with patch.object(h, "run", side_effect=[b"WayDroid_x86_64_Device", b"Starting"] ) as call:
            result = h.inject(cfg, args)
        self.assertEqual(result["input"], "launch")
        self.assertEqual(
            call.call_args.args[0][-2:],
            ["-n", "nz.presley.stoneandbanner/.MainActivity"],
        )

    def test_failed_input_still_captures_an_auditable_frame(self):
        args = argparse.Namespace(
            root=self.root, command="act", flow="failed-launch", kind="screen-open",
            action="Attempt launch", expected="Home", settle_ms=0,
            input="launch",
        )
        with patch.object(h, "inject", side_effect=RuntimeError("blocked")), \
             patch.object(h, "take_png", return_value=PNG):
            with self.assertRaises(SystemExit):
                h.cmd_capture(args)
        rows, _ = h.effective(self.root)
        self.assertEqual(len(rows), 1)
        self.assertIn("blocked", rows[0]["input"]["failed"])
        self.assertTrue((self.root / rows[0]["screenshot"]).is_file())

    def test_linux_input_is_wayland_scoped(self):
        args = argparse.Namespace(
            input="key", key="Tab", x=None, y=None, end_x=None, end_y=None,
            text=None, duration_ms=300,
        )
        with patch.object(h, "run", return_value=b"") as call:
            result = h.inject(self.cfg, args)
        self.assertEqual(result["key"], "Tab")
        self.assertEqual(call.call_args.args[0], ["wtype", "-k", "Tab"])
        self.assertEqual(
            call.call_args.kwargs["env"]["WAYLAND_DISPLAY"], "wayland-test"
        )
        args.input = "tap"
        with self.assertRaises(SystemExit):
            h.inject(self.cfg, args)


if __name__ == "__main__":
    unittest.main()
