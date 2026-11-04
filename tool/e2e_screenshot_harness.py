#!/usr/bin/env python3
"""Stone & Banner live UI screenshot/action evidence, for Glass/Nox Linux and Waydroid.

The harness records what it did, not what a screenshot proves. Visual review is
an explicit, later step. Never use its Android mode against a physical device.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time
import uuid
import zlib
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
SEVERITIES = ("none", "minor", "major", "critical")
VERDICTS = ("PASS", "FAIL", "LIMITED")


def die(message: str) -> None:
    raise SystemExit(message)


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")[:48] or "action"


def timestamp() -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    return now.isoformat(timespec="milliseconds"), now.astimezone(
        ZoneInfo("Pacific/Auckland")
    ).isoformat(timespec="milliseconds")


def load_config(root: Path) -> dict:
    path = root / "session.json"
    if not path.is_file():
        die(f"Missing {path}; run init first")
    cfg = json.loads(path.read_text())
    if cfg["host"].lower() != socket.gethostname().lower():
        die(f"Session host {cfg['host']} differs from {socket.gethostname()}")
    return cfg


def run(argv: list[str], *, env: dict | None = None, timeout: int = 20) -> bytes:
    result = subprocess.run(
        argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, check=False,
    )
    if result.returncode:
        raise RuntimeError(
            f"{argv!r} exited {result.returncode}: "
            f"{result.stderr.decode(errors='replace')[-1200:]}"
        )
    return result.stdout


def waydroid(cfg: dict) -> list[str]:
    if cfg["platform"] != "waydroid":
        die("Android input is only allowed in a Waydroid session")
    prefix = ["adb", "-s", cfg["adb_serial"]]
    model = run(prefix + ["shell", "getprop", "ro.product.model"]).decode().strip()
    if "waydroid" not in model.lower():
        die(f"Refusing to control non-Waydroid Android device: {model!r}")
    return prefix


def linux_env(cfg: dict) -> dict:
    env = os.environ.copy()
    env["WAYLAND_DISPLAY"] = cfg["wayland_display"]
    env["XDG_RUNTIME_DIR"] = cfg["runtime_dir"]
    return env


def take_png(cfg: dict) -> bytes:
    if cfg["platform"] == "linux":
        data = run(["grim", "-t", "png", "-"], env=linux_env(cfg))
    elif cfg["platform"] == "waydroid":
        data = run(waydroid(cfg) + ["exec-out", "screencap", "-p"])
    else:
        die("Unsupported platform")
    dimensions(data)  # fail rather than store a black/invalid file format
    return data


def dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or not data.startswith(PNG_MAGIC):
        raise ValueError("Capture is not a PNG")
    pos, size, has_data, has_end = 8, None, False, False
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        end = pos + 12 + length
        if end > len(data):
            raise ValueError("Truncated PNG chunk")
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + body) & 0xffffffff != crc:
            raise ValueError("PNG chunk checksum mismatch")
        if kind == b"IHDR" and size is None and length == 13:
            size = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            has_data = True
        elif kind == b"IEND":
            has_end = True
            if end != len(data):
                raise ValueError("Trailing bytes after PNG end")
            break
        pos = end
    if size is None or not has_data or not has_end:
        raise ValueError("Incomplete PNG chunks")
    width, height = size
    if not 1 <= width <= 16384 or not 1 <= height <= 16384:
        raise ValueError("Invalid screenshot dimensions")
    return width, height


def inject(cfg: dict, args: argparse.Namespace) -> dict:
    kind = args.input
    if cfg["platform"] == "linux":
        if kind == "key":
            cmd = ["wtype", "-k", args.key]
        elif kind == "text":
            cmd = ["wtype", args.text]
        else:
            die("Linux headless sessions support key/text; use Waydroid for tap/swipe")
        run(cmd, env=linux_env(cfg))
    else:
        adb = waydroid(cfg)
        if kind == "key":
            cmd = adb + ["shell", "input", "keyevent", args.key]
        elif kind == "text":
            cmd = adb + ["shell", "input", "text", args.text]
        elif kind == "tap":
            cmd = adb + ["shell", "input", "tap", str(args.x), str(args.y)]
        elif kind == "launch":
            cmd = adb + ["shell", "am", "start", "-n",
                         "nz.presley.stoneandbanner/.MainActivity"]
        elif kind == "swipe":
            cmd = adb + ["shell", "input", "swipe", str(args.x), str(args.y),
                         str(args.end_x), str(args.end_y), str(args.duration_ms)]
        else:
            die(f"Unsupported input: {kind}")
        run(cmd)
    coordinates = {
        "x": args.x, "y": args.y, "end_x": args.end_x, "end_y": args.end_y
    } if kind in ("tap", "swipe") else None
    return {"input": kind, "key": args.key if kind == "key" else None,
            "text": args.text if kind == "text" else None,
            "coordinates": coordinates,
            "duration_ms": args.duration_ms if kind == "swipe" else None}


def records(root: Path) -> list[dict]:
    path = root / "manifest.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def effective(root: Path) -> tuple[list[dict], list[dict]]:
    entries = records(root)
    captures = [dict(x) for x in entries if x["type"] == "capture"]
    by_id = {x["id"]: x for x in captures}
    for entry in entries:
        if entry["type"] == "review" and entry["capture_id"] in by_id:
            by_id[entry["capture_id"]].update({
                k: entry[k] for k in ("actual", "verdict", "critique", "severity",
                                      "retest_id", "reviewed_at")
            })
    return captures, [x for x in entries if x["type"] == "flow"]


def append(root: Path, record: dict) -> None:
    root.mkdir(parents=True, exist_ok=True)
    with (root / "manifest.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def capture(root: Path, cfg: dict, args: argparse.Namespace, inp: dict | None) -> None:
    # Serialize the count, screenshot and record so parallel callers cannot overwrite.
    with (root / ".capture.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        row = 1 + sum(x["type"] == "capture" for x in records(root))
        if args.settle_ms:
            time.sleep(args.settle_ms / 1000)
        data = take_png(cfg)
        width, height = dimensions(data)
        utc, nz = timestamp()
        name = (f"{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-"
                f"{time.time_ns() % 1000000000:09d}-{cfg['host'].lower()}-"
                f"{cfg['platform']}-{row:04d}-{slug(args.action)}-"
                f"{uuid.uuid4().hex[:8]}.png")
        with (root / name).open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        append(root, {
            "type": "capture", "id": row, "flow": args.flow,
            "kind": args.kind, "action": args.action, "input": inp,
            "expected": args.expected, "actual": "UNREVIEWED",
            "verdict": "PENDING", "critique": "UNREVIEWED", "severity": "unreviewed",
            "retest_id": None, "captured_at": utc, "captured_at_nz": nz,
            "host": cfg["host"], "platform": cfg["platform"],
            "app_version": cfg["app_version"], "build_id": cfg["build_id"],
            "source_revision": cfg["source_revision"],
            "device": cfg.get("adb_serial") or cfg.get("wayland_display"),
            "width": width, "height": height, "screenshot": name,
            "size_bytes": len(data), "settle_ms": args.settle_ms,
        })
    print(f"CAPTURE #{row} {root / name} ({width}x{height}); visual review PENDING")


def cmd_init(args: argparse.Namespace) -> None:
    root = args.root
    root.mkdir(parents=True, exist_ok=True)
    path = root / "session.json"
    if path.exists():
        die(f"Session already exists: {path}; don't overwrite evidence")
    hostname = socket.gethostname()
    if args.host.lower() != hostname.lower():
        die(f"Host label {args.host} does not match running machine {hostname}")
    if args.platform == "waydroid" and not args.adb_serial:
        die("--adb-serial is required for Waydroid")
    if args.platform == "linux" and not args.wayland_display:
        die("--wayland-display is required for Linux")
    cfg = {
        "session": args.session, "host": hostname, "platform": args.platform,
        "app_version": args.app_version, "build_id": args.build_id,
        "source_revision": args.source_revision, "adb_serial": args.adb_serial,
        "wayland_display": args.wayland_display,
        "runtime_dir": args.runtime_dir, "started_at": timestamp()[0],
        "protocol_version": 1,
    }
    if args.platform == "waydroid":
        waydroid(cfg)  # refuse Samsung/physical Android at initialization
    with path.open("x") as handle:
        json.dump(cfg, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(path)


def cmd_capture(args: argparse.Namespace) -> None:
    cfg = load_config(args.root)
    inp = None
    if args.command == "act":
        try:
            inp = inject(cfg, args)
        except Exception as exc:
            # Preserve attempted action and take a screenshot even if injection failed.
            inp = {"input": args.input, "failed": str(exc)}
            print(f"INPUT FAILURE: {exc}", file=sys.stderr)
    capture(args.root, cfg, args, inp)
    if inp and inp.get("failed"):
        raise SystemExit(1)


def cmd_review(args: argparse.Namespace) -> None:
    load_config(args.root)
    captures, _ = effective(args.root)
    if not any(x["id"] == args.id for x in captures):
        die(f"Unknown capture ID {args.id}")
    if args.severity == "none" and args.verdict == "FAIL":
        die("FAIL requires a defect severity")
    append(args.root, {
        "type": "review", "capture_id": args.id, "actual": args.actual,
        "verdict": args.verdict, "critique": args.critique,
        "severity": args.severity, "retest_id": args.retest_id,
        "reviewed_at": timestamp()[0],
    })
    print(f"REVIEW #{args.id}: {args.verdict}")


def cmd_complete(args: argparse.Namespace) -> None:
    load_config(args.root)
    captures, _ = effective(args.root)
    flow = [x for x in captures if x["flow"] == args.flow]
    if (len(flow) < 2 or not any(x["kind"] == "screen-open" for x in flow)
            or not any(x["kind"] == "action" for x in flow)
            or any(x["verdict"] == "PENDING" for x in flow)):
        die("Cannot complete flow: requires screen-open, action and full visual review")
    append(args.root, {"type": "flow", "flow": args.flow, "status": args.status,
                       "notes": args.notes, "completed_at": timestamp()[0],
                       "capture_ids": [x["id"] for x in flow]})
    print(f"FLOW {args.flow}: {args.status} ({len(flow)} captures)")


def report(root: Path) -> str:
    cfg = load_config(root)
    captures, flows = effective(root)
    out = [
        f"# Stone & Banner — {cfg['session']} live screenshot manifest",
        "", f"Platform: **{cfg['host']} {cfg['platform']}** · "
        f"version **{cfg['app_version']}** · build **{cfg['build_id']}** · "
        f"source **{cfg['source_revision']}**",
        "", "Every action is recorded at capture time; review is separate and explicit.",
        "",
        "| ID / Flow | Time (NZ) / Kind / Input | Action / Expected / Actual | Screenshot | Visual critique / Severity / Retest |",
        "| --- | --- | --- | --- | --- |",
    ]
    def cell(s: object) -> str:
        return str(s if s is not None else "—").replace("|", "\\|").replace("\n", " ")
    for x in captures:
        inp = json.dumps(x["input"], ensure_ascii=False) if x["input"] else "screen open"
        out.append(
            f"| {x['id']:04d} / {cell(x['flow'])} | {cell(x['captured_at_nz'])} / "
            f"{cell(x['kind'])} / {cell(inp)} | {cell(x['action'])} "
            f"/ **Expected:** {cell(x['expected'])} / **Actual:** {cell(x['actual'])} "
            f"| [PNG]({x['screenshot']}) ({x['width']}×{x['height']}) "
            f"| **{cell(x['verdict'])}**: {cell(x['critique'])}; "
            f"severity {cell(x['severity'])}; retest {cell(x['retest_id'])} |"
        )
    out += ["", "## Flow outcomes", ""]
    for x in flows:
        out.append(f"- **{x['flow']}**: {x['status']} — {x['notes']} "
                   f"(captures {x['capture_ids']})")
    if not flows:
        out.append("- No completed flows recorded.")
    return "\n".join(out) + "\n"


def cmd_report(args: argparse.Namespace) -> None:
    content = report(args.root)
    path = args.root / "SCREENSHOT-MANIFEST.md"
    path.write_text(content)
    print(path)


def cmd_verify(args: argparse.Namespace) -> None:
    cfg = load_config(args.root)
    captures, flows = effective(args.root)
    errors = []
    names = set()
    for row in captures:
        name = row["screenshot"]
        if name in names:
            errors.append(f"duplicate filename {name}")
        names.add(name)
        try:
            dims = dimensions((args.root / name).read_bytes())
            if dims != (row["width"], row["height"]):
                errors.append(f"#{row['id']} mismatched dimensions")
        except (OSError, ValueError) as exc:
            errors.append(f"#{row['id']} invalid screenshot: {exc}")
        if row["verdict"] == "PENDING":
            errors.append(f"#{row['id']} awaiting visual review")
        if not row["critique"] or row["critique"] == "UNREVIEWED":
            errors.append(f"#{row['id']} missing visual critique")
    if [x["id"] for x in captures] != list(range(1, len(captures) + 1)):
        errors.append("noncontiguous capture IDs")
    complete = {x["flow"] for x in flows if x["status"] == "PASS"}
    if len(complete) < args.require_flows:
        errors.append(f"only {len(complete)} PASS flow(s), need {args.require_flows}")
    if errors:
        for e in errors:
            print("ERROR:", e, file=sys.stderr)
        raise SystemExit(1)
    print(f"VERIFIED {cfg['host']} {cfg['platform']}: "
          f"{len(captures)} reviewed PNGs, {len(complete)} PASS flows, "
          "unique names and PNG dimensions")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    i = sub.add_parser("init")
    i.add_argument("--root", type=Path, required=True)
    i.add_argument("--session", required=True)
    i.add_argument("--host", choices=["glass", "nox"], required=True)
    i.add_argument("--platform", choices=["linux", "waydroid"], required=True)
    i.add_argument("--app-version", required=True)
    i.add_argument("--build-id", required=True)
    i.add_argument("--source-revision", required=True)
    i.add_argument("--adb-serial")
    i.add_argument("--wayland-display")
    i.add_argument("--runtime-dir", default=f"/run/user/{os.getuid()}")
    i.set_defaults(func=cmd_init)
    for kind in ("capture", "act"):
        s = sub.add_parser(kind)
        s.add_argument("--root", type=Path, required=True)
        s.add_argument("--flow", required=True)
        s.add_argument("--action", required=True)
        s.add_argument("--expected", required=True)
        s.add_argument("--kind", choices=["screen-open", "action"], required=True)
        s.add_argument("--settle-ms", type=int, default=250 if kind == "act" else 0)
        if kind == "act":
            s.add_argument("--input", choices=["key", "text", "tap", "swipe", "launch"], required=True)
            s.add_argument("--key")
            s.add_argument("--text")
            for value in ("x", "y", "end_x", "end_y"):
                s.add_argument("--" + value.replace("_", "-"), type=int)
            s.add_argument("--duration-ms", type=int, default=300)
        s.set_defaults(func=cmd_capture)
    s = sub.add_parser("review")
    s.add_argument("--root", type=Path, required=True)
    s.add_argument("--id", type=int, required=True)
    s.add_argument("--actual", required=True)
    s.add_argument("--verdict", choices=VERDICTS, required=True)
    s.add_argument("--critique", required=True)
    s.add_argument("--severity", choices=SEVERITIES, required=True)
    s.add_argument("--retest-id")
    s.set_defaults(func=cmd_review)
    s = sub.add_parser("complete")
    s.add_argument("--root", type=Path, required=True)
    s.add_argument("--flow", required=True)
    s.add_argument("--status", choices=VERDICTS, required=True)
    s.add_argument("--notes", required=True)
    s.set_defaults(func=cmd_complete)
    for kind, method in (("report", cmd_report), ("verify", cmd_verify)):
        s = sub.add_parser(kind)
        s.add_argument("--root", type=Path, required=True)
        if kind == "verify":
            s.add_argument("--require-flows", type=int, default=0)
        s.set_defaults(func=method)
    return p


if __name__ == "__main__":
    args = parser().parse_args()
    args.func(args)
