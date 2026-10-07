"""Owned-window exploration of ordering strategies; never release acceptance.

Uses real CoverWindow/material code in two separate app processes. Retains
raw samples and commands. Capture is optional and stays in the local run root.
"""

import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import time
from pathlib import Path


def wait_for(path, process, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"owned process exited with {process.returncode}: {path}")
        if path.exists():
            return json.loads(path.read_text())
        time.sleep(0.02)
    raise TimeoutError(str(path))


def command(run, role, value, process):
    path = run / f"{role}-command"
    temporary = path.with_suffix(".pending")
    temporary.write_text(value)
    temporary.replace(path)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if path.read_text() == "":
            return
        if process.poll() is not None:
            raise RuntimeError(f"{role} exited with {process.returncode}")
        time.sleep(0.01)
    raise TimeoutError(f"{role} did not consume {value}")


def build(root, output):
    sources = ["Surfaces", "CoverWindow", "RibbonGeometry", "RibbonRenderer",
               "RibbonDisplayDriver", "AttachedPaperGeometry"]
    binary = output / "ActivationRelationTrial"
    bridge = root / "Sources/WindowListBridge"
    bridge_object = output / "WindowListBridge.o"
    subprocess.run(["clang", "-O2", "-I", str(bridge / "include"), "-c",
                    str(bridge / "WindowListBridge.c"), "-o", str(bridge_object)], check=True)
    subprocess.run(["swiftc", "-O", "-parse-as-library",
                    "-import-objc-header", str(bridge / "include/WindowListBridge.h"),
                    *[str(root / "Sources/Parchmatte" / f"{name}.swift") for name in sources],
                    str(root / "Tests/Harness/activation_relation_trial.swift"), str(bridge_object),
                    "-o", str(binary)], check=True)
    executables = {}
    for role in ["fixture", "overlay"]:
        name = "Activation" + role.title()
        app = output / f"{name}.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": f"com.parchmatte.activation-{role}-trial",
            "CFBundleName": name, "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL", "NSHighResolutionCapable": True,
        }))
        executables[role] = app / "Contents/MacOS" / name
        shutil.copy2(binary, executables[role])
        shutil.copytree(root / "Sources/Parchmatte/Textures", app / "Contents/Resources/Textures")
    subprocess.run(["swiftc", "-O", str(root / "Tests/Harness/actprobe.swift"),
                    "-o", str(output / "actprobe")], check=True)
    return executables


def check_session(executable, run):
    result = subprocess.run([executable, "--preflight"], capture_output=True, text=True, check=False)
    with (run / "session.jsonl").open("a") as handle:
        handle.write(result.stdout)
    if result.returncode != 0:
        raise RuntimeError("GUI session is locked, unavailable, or belongs to another user: " + result.stdout.strip())


def wait_for_occlusion(run, process, visible, after_command, seconds=2):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"overlay exited during callback control: {process.returncode}")
        # Exclude any still-being-written trailing record.
        seen_command = False
        for line in (run / "overlay-events.jsonl").read_text().split("\n")[:-1]:
            event = json.loads(line)
            if event.get("event") == "command" and event.get("command") == after_command:
                seen_command = True
            if seen_command and event.get("event") == "occlusion" and event.get("visible") == visible:
                return event
        time.sleep(0.02)
    raise RuntimeError(f"occlusion callback positive control did not report visible={visible}; trial is inconclusive")


def validate_native_transitions(run, identity, trigger):
    """Input delivery is a positive control, independent of paper coverage."""
    events = [json.loads(line) for line in (run / "fixture-events.jsonl").read_text().split("\n")[:-1]]
    first = next((event["t"] for event in events
                  if event.get("event") == "command" and
                  event.get("command") in ["click-b", "cycle"]), None)
    if first is None:
        raise RuntimeError(f"{trigger} had no native input commands; trial is inconclusive")
    actual = [event["window"] for event in events
              if event.get("event") == "key" and event["t"] > first]
    expected = [identity["neighbor"] if i % 2 == 0 else identity["target"] for i in range(20)]
    (run / "native-input-control.json").write_text(json.dumps({
        "trigger": trigger, "expected": expected, "actual": actual,
        "valid": actual == expected}, indent=2) + "\n")
    if actual != expected:
        raise RuntimeError(f"{trigger} did not deliver all 20 expected key-window changes; trial is inconclusive")


def trial(mode, output, executables, capture, trigger="programmatic"):
    run = output / (mode if trigger == "programmatic" else f"{trigger}-{mode}")
    run.mkdir()
    processes = []
    handles = []
    fixture = overlay = None
    try:
        check_session(executables["fixture"], run)
        def start(args, name):
            handle = (run / f"{name}.log").open("w")
            handles.append(handle)
            process = subprocess.Popen([str(arg) for arg in args], stdout=handle, stderr=subprocess.STDOUT)
            processes.append(process)
            return process

        fixture = start([executables["fixture"], "fixture", mode, run], "fixture")
        identity = wait_for(run / "fixture.json", fixture)
        time.sleep(0.3)
        if mode == "child":
            paper = {"pid": identity["pid"], "cover": identity["cover"]}
        else:
            overlay = start([executables["overlay"], "overlay", mode, run], "overlay")
            paper = wait_for(run / "overlay.json", overlay)
        time.sleep(0.3)
        if overlay and mode in ["occlusion", "occlusion-inset", "sentinel"]:
            command(run, "overlay", "hide-paper", overlay)
            hidden = wait_for_occlusion(run, overlay, False, "hide-paper")
            command(run, "overlay", "show-paper", overlay)
            shown = wait_for_occlusion(run, overlay, True, "show-paper")
            (run / "callback-control.json").write_text(json.dumps({"hidden": hidden, "shown": shown}, indent=2) + "\n")
            check_session(executables["fixture"], run)
        seconds = 10
        probe = start([output / "actprobe", "OwnedFixture", seconds, "--timeline", "--assert-covered",
                       f"--pid={identity['pid']}", f"--window={identity['target']}",
                       f"--cover-pid={paper['pid']}", f"--cover-window={paper['cover']}",
                       f"--neighbor={identity['neighbor']}", f"--jsonl={run / 'samples.jsonl'}"], "probe")
        recorder = None
        if capture:
            recorder = start([capture, run / "video.mp4", seconds, 200, 150, 1100, 760], "capture")
            wait_for(run / "video.ready.json", recorder)
        time.sleep(0.5)
        # Separate the compositor ordering hypothesis from native input
        # delivery, and verify native changes through the owned delegate.
        for i in range(20):
            if i % 3 == 0:
                check_session(executables["fixture"], run)
            if trigger == "cycle":
                value = "cycle"
            else:
                value = "b" if i % 2 == 0 else "a"
                if trigger == "click":
                    value = "click-" + value
            command(run, "fixture", value, fixture)
            time.sleep(0.3)
        probe_status = probe.wait(timeout=15)
        if probe_status not in [0, 1]:
            raise RuntimeError(f"probe failed: {probe_status}")
        if trigger != "programmatic":
            validate_native_transitions(run, identity, trigger)
        if recorder and recorder.wait(timeout=15) != 0:
            raise RuntimeError("capture failed")
        check_session(executables["fixture"], run)
        if overlay:
            command(run, "overlay", "quit", overlay)
            overlay.wait(timeout=3)
        command(run, "fixture", "quit", fixture)
        fixture.wait(timeout=3)
        return {"mode": mode, "trigger": trigger, "coverageGateExit": probe_status,
                "probe": (run / "probe.log").read_text().strip()}
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
        for handle in handles:
            handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new, local-only run directory")
    parser.add_argument("--capture", type=Path, help="optional compiled activation_capture.swift executable")
    parser.add_argument("--trigger", choices=["programmatic", "click", "cycle"], default="programmatic")
    parser.add_argument("--modes", nargs="+", choices=["poll45", "displaylink", "lifted", "clip45", "clip120", "child", "occlusion", "occlusion-inset", "sentinel"],
                        default=["poll45", "lifted", "clip45", "clip120", "child", "occlusion"])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if args.capture and not args.capture.is_file():
        raise FileNotFoundError(args.capture)
    root = Path(__file__).resolve().parents[2]
    (output / "source.patch").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=root))
    (output / "source-revision.txt").write_bytes(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root))
    inputs = [*root.glob("Sources/Parchmatte/*.swift"),
              *root.glob("Sources/Parchmatte/Textures/*.png"),
              root / "Sources/WindowListBridge/WindowListBridge.c",
              root / "Sources/WindowListBridge/include/WindowListBridge.h",
              root / "Tests/Harness/activation_relation_trial.swift",
              root / "Tests/Harness/activation_capture.swift",
              root / "Tests/Harness/activation_frame_stats.swift",
              Path(__file__).resolve(), root / "Tests/Harness/actprobe.swift"]
    (output / "input-hashes.json").write_text(json.dumps({
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in inputs}, indent=2) + "\n")
    if args.capture:
        (output / "capture-sha256.txt").write_text(hashlib.sha256(args.capture.read_bytes()).hexdigest() + "\n")
    # New untracked harness files are not included by git diff. Preserve
    # their exact contents, plus compiler source inputs, alongside the hashes.
    for path in inputs:
        if path.suffix != ".png":
            snapshot = output / "source-inputs" / path.relative_to(root)
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, snapshot)
    executables = build(root, output)
    results = []
    for mode in args.modes:
        result = trial(mode, output, executables, args.capture, args.trigger)
        results.append(result)
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(result["mode"] + ": " + result["probe"], flush=True)


if __name__ == "__main__":
    main()
