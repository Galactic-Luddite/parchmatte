#!/usr/bin/env python3
"""Build an internal experiment-tracker envelope (owner-only schema v1) from a
run_audit.sh results folder: one execution per suite, pass/fail and measured
metrics parsed from each log, every log attached as a hashed artifact.

Usage: make_envelope.py <results dir> <run id> <flavor> <started> <ended>
"""
import hashlib
import json
import platform
import re
import socket
import subprocess
import sys
from pathlib import Path

out, run_id, flavor, started, ended = Path(sys.argv[1]), *sys.argv[2:6]
root = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True).stdout.strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def numbers(pattern, text):
    return [float(x) for x in re.findall(pattern, text, re.M)]


executions, artifacts = [], []
totals = {"total_checks_passed": 0.0, "total_checks_failed": 0.0}
for log in sorted(out.glob("*.log")):
    suite, text = log.stem, log.read_text(errors="replace")
    passed = float(len(re.findall(r"^PASS ", text, re.M)))
    failed = float(len(re.findall(r"^FAIL ", text, re.M)))
    exit_code = numbers(r"^exit=(\d+)", text)
    metrics = {"checks_passed": passed, "checks_failed": failed,
               "exit_code": exit_code[-1] if exit_code else -1.0}
    if suite == "perf":
        for label, cpu, wake in re.findall(r"^(H\w+)[^:]*: cpu_avg=([\d.]+)% idle_wakeups_avg=([\d.]+)", text, re.M):
            metrics[f"{label.lower()}_cpu_pct"] = float(cpu)
            metrics[f"{label.lower()}_wakeups_per_s"] = float(wake)
    if suite in ("drag", "spaces"):
        for key in ("samples", "uncovered", "misaligned", "maxErrorPx"):
            values = numbers(rf"{key}=(\d+)", text)
            if values:
                metrics[key.lower()] = max(values) if key == "maxErrorPx" else sum(values)
    if suite == "netwatch":
        metrics["sockets_seen"] = (numbers(r"sockets_seen=(\d+)", text) or [-1.0])[-1]
    if suite == "fuzz":
        survived = numbers(r"fuzz: (\d+) survived", text)
        crashed = numbers(r"survived, (\d+) crashed", text)
        metrics["launches_survived"] = survived[-1] if survived else -1.0
        metrics["launches_crashed"] = crashed[-1] if crashed else -1.0
    if suite == "softness":
        diff = numbers(r"source vs step0: ([\d.]+)", text)
        metrics["step0_vs_source"] = diff[-1] if diff else -1.0
    totals["total_checks_passed"] += passed
    totals["total_checks_failed"] += failed
    executions.append({
        "execution_id": f"{run_id}:{suite}", "variant": suite,
        "params": {"suite": suite}, "metrics": metrics,
        "tags": {"suite_result": "pass" if metrics["exit_code"] == 0 else "fail"},
    })
    artifacts.append({
        "path": log.name, "sha256": sha256(log), "media_type": "text/plain",
        "classification": "public", "export": True, "execution_id": f"{run_id}:{suite}",
    })

manifest = root / "docs" / "audit" / "audit-manifest.json"
screens = subprocess.run([str(Path(__file__).parent / "bin" / "screens")], capture_output=True, text=True).stdout
envelope = {
    "schema_version": 1,
    "experiment": {"name": "parchmatte-release", "domain": "parchmatte", "run_id": run_id,
                   "started_at": started, "ended_at": ended},
    "source": {"repository": "Galactic-Luddite/parchmatte", "commit": git("rev-parse", "HEAD"),
               "dirty": bool(git("status", "--porcelain", "--", "Sources", "scripts")),
               "host": socket.gethostname().split(".")[0]},
    "axis": {"name": "suite", "controlled": ["build_flavor", "macos_version", "display_layout"],
             "variants": [e["variant"] for e in executions]},
    "params": {"build_flavor": flavor, "macos_version": platform.mac_ver()[0],
               "display_layout": " | ".join(line.split(" frame=")[0].split(" ", 1)[1] + " @" + line.split("scale=")[1]
                                            for line in screens.strip().splitlines() if "scale=" in line)},
    "metrics": totals,
    "tags": {"audit": "release-1.0",
             "audit_result": "pass" if totals["total_checks_failed"] == 0
             and all(e["tags"]["suite_result"] == "pass" for e in executions) else "fail"},
    "executions": executions,
    "artifacts": artifacts,
    "bindings": {"domain_manifest_sha256": sha256(manifest), "decision_sha256": None},
}
json.dump(envelope, sys.stdout, indent=2)
