#!/usr/bin/env python3
"""Build, install, and launch Reflect on a physical iOS device.

Interactive flow:
    1. Pick a branch — main, develop, or a free-text feature branch.
    2. Check out (and fast-forward) that branch.
    3. Pick a connected iPhone (auto-selected if only one).
    4. Build for that device, install, and launch.

Non-interactive usage:
    python3 scripts/run_on_device.py --branch develop
    python3 scripts/run_on_device.py --branch feature/space --device 00008120-0011...
    python3 scripts/run_on_device.py --no-git          # build current checkout as-is

Requires Xcode 15+ (uses `xcrun devicectl`) and a paired, unlocked device.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# --- Project constants -------------------------------------------------------

SCHEME = "Reflect"
PROJECT = "Reflect.xcodeproj"
BUNDLE_ID = "xyz.nandamochammad.Reflect"
DERIVED_DATA = "build"  # relative to repo root
REPO_ROOT = Path(__file__).resolve().parent.parent

# ANSI colors (skipped when stdout is not a TTY).
_TTY = sys.stdout.isatty()
def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text
def bold(t: str) -> str: return _c("1", t)
def green(t: str) -> str: return _c("32", t)
def yellow(t: str) -> str: return _c("33", t)
def red(t: str) -> str: return _c("31", t)
def cyan(t: str) -> str: return _c("36", t)


# --- Shell helpers -----------------------------------------------------------

def run(cmd: list[str], *, capture: bool = False, check: bool = True,
        cwd: Path | None = None) -> subprocess.CompletedProcess:
    """Run a command, streaming output unless `capture` is set."""
    printable = " ".join(str(c) for c in cmd)
    print(cyan(f"$ {printable}"))
    return subprocess.run(
        cmd,
        cwd=str(cwd or REPO_ROOT),
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def capture(cmd: list[str], *, check: bool = True) -> str:
    return run(cmd, capture=True, check=check).stdout.strip()


def die(msg: str) -> "None":
    print(red(f"\n✗ {msg}"))
    sys.exit(1)


# --- Git ---------------------------------------------------------------------

def current_branch() -> str:
    return capture(["git", "rev-parse", "--abbrev-ref", "HEAD"])


def choose_branch(preset: str | None) -> str:
    if preset:
        return preset
    print(bold("\nWhich branch do you want to run?"))
    print(f"  {green('1')}) main")
    print(f"  {green('2')}) develop")
    print(f"  {green('3')}) feature branch (type its name)")
    while True:
        choice = input(bold("Select [1/2/3]: ")).strip()
        if choice == "1":
            return "main"
        if choice == "2":
            return "develop"
        if choice == "3":
            name = input("Feature branch name: ").strip()
            if name:
                return name
            print(yellow("  Branch name can't be empty."))
        else:
            print(yellow("  Enter 1, 2, or 3."))


def prepare_branch(branch: str) -> None:
    """Fetch, guard against a dirty tree, check out, and fast-forward."""
    run(["git", "fetch", "origin", "--prune"])

    dirty = capture(["git", "status", "--porcelain"])
    if dirty and current_branch() != branch:
        print(yellow("\nWorking tree has uncommitted changes:"))
        print(dirty)
        ans = input(yellow("Stash them before switching? [y/N]: ")).strip().lower()
        if ans == "y":
            run(["git", "stash", "push", "-u", "-m", "run_on_device autostash"])
        else:
            die("Aborting so your changes aren't disturbed. Commit/stash, or use --no-git.")

    # Local branch exists?
    exists_local = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
        cwd=str(REPO_ROOT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0

    if exists_local:
        run(["git", "checkout", branch])
    else:
        # Track the remote branch if it exists there.
        exists_remote = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}"],
            cwd=str(REPO_ROOT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0
        if not exists_remote:
            die(f"Branch '{branch}' not found locally or on origin.")
        run(["git", "checkout", "-b", branch, "--track", f"origin/{branch}"])

    # Fast-forward if a remote tracking branch exists (don't fail if it doesn't).
    run(["git", "pull", "--ff-only"], check=False)


# --- Device discovery --------------------------------------------------------

def list_devices() -> list[dict]:
    """Return connected physical iOS devices via `devicectl`."""
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        out_path = tmp.name
    try:
        run(["xcrun", "devicectl", "list", "devices", "--json-output", out_path],
            capture=True)
        with open(out_path) as fh:
            data = json.load(fh)
    finally:
        os.unlink(out_path)

    devices = []
    for dev in data.get("result", {}).get("devices", []):
        hw = dev.get("hardwareProperties", {})
        conn = dev.get("connectionProperties", {})
        if hw.get("platform") != "iOS":
            continue
        devices.append({
            "name": dev.get("deviceProperties", {}).get("name", "Unknown"),
            "os": dev.get("deviceProperties", {}).get("osVersionNumber", "?"),
            "udid": hw.get("udid") or dev.get("identifier"),
            "tunnel": conn.get("tunnelState", "unknown"),
            "transport": conn.get("transportType", "unknown"),
        })
    # Reachable devices (tunnel connected) first.
    devices.sort(key=lambda d: d["tunnel"] != "connected")
    return devices


def choose_device(devices: list[dict], preset: str | None) -> dict:
    if preset:
        for d in devices:
            if preset in (d["udid"], d["name"]):
                return d
        die(f"Device '{preset}' not found among connected devices.")

    if not devices:
        die("No physical iOS device detected. Connect and unlock your iPhone, "
            "and trust this Mac if prompted.")
    if len(devices) == 1:
        d = devices[0]
        print(green(f"\nUsing device: {d['name']} (iOS {d['os']})"))
        return d

    print(bold("\nConnected devices:"))
    for i, d in enumerate(devices, 1):
        mark = green("●") if d["tunnel"] == "connected" else yellow("○")
        print(f"  {green(str(i))}) {mark} {d['name']} — iOS {d['os']} "
              f"({d['transport']}, {d['tunnel']})")
    while True:
        choice = input(bold(f"Select [1-{len(devices)}]: ")).strip()
        if choice.isdigit() and 1 <= int(choice) <= len(devices):
            return devices[int(choice) - 1]
        print(yellow(f"  Enter a number 1-{len(devices)}."))


# --- Build / install / launch ------------------------------------------------

def build(udid: str, configuration: str) -> Path:
    run([
        "xcodebuild",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-configuration", configuration,
        "-destination", f"platform=iOS,id={udid}",
        "-derivedDataPath", DERIVED_DATA,
        "-allowProvisioningUpdates",
        "build",
    ])
    products = REPO_ROOT / DERIVED_DATA / "Build" / "Products" / f"{configuration}-iphoneos"
    apps = glob.glob(str(products / "*.app"))
    if not apps:
        die(f"Build finished but no .app found in {products}")
    return Path(apps[0])


def install_and_launch(udid: str, app_path: Path) -> None:
    print(bold(f"\nInstalling {app_path.name} …"))
    run(["xcrun", "devicectl", "device", "install", "app",
         "--device", udid, str(app_path)])

    print(bold("Launching …"))
    run(["xcrun", "devicectl", "device", "process", "launch",
         "--device", udid, "--terminate-existing", BUNDLE_ID])


# --- Main --------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build, install, and launch Reflect on a physical iOS device.")
    parser.add_argument("-b", "--branch",
                        help="Branch to run (e.g. main, develop, feature/x). "
                             "Omit for an interactive menu.")
    parser.add_argument("-d", "--device",
                        help="Device UDID or name. Omit to auto-select / prompt.")
    parser.add_argument("-c", "--configuration", default="Debug",
                        help="Build configuration (default: Debug).")
    parser.add_argument("--no-git", action="store_true",
                        help="Skip all git operations; build the current checkout.")
    args = parser.parse_args()

    if not (REPO_ROOT / PROJECT).exists():
        die(f"Can't find {PROJECT} at {REPO_ROOT}")

    if args.no_git:
        print(green(f"\nSkipping git — building current branch: {current_branch()}"))
    else:
        branch = choose_branch(args.branch)
        print(bold(f"\n▶ Preparing branch: {branch}"))
        prepare_branch(branch)

    devices = list_devices()
    device = choose_device(devices, args.device)
    udid = device["udid"]

    print(bold(f"\n▶ Building {SCHEME} ({args.configuration}) for {device['name']} …"))
    app_path = build(udid, args.configuration)

    install_and_launch(udid, app_path)

    print(green(f"\n✓ {app_path.name} is running on {device['name']}."))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        die(f"Command failed (exit {exc.returncode}): {' '.join(map(str, exc.cmd))}")
    except KeyboardInterrupt:
        print(yellow("\nCancelled."))
        sys.exit(130)
