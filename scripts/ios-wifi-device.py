#!/usr/bin/env python3
"""Use an existing pairing record and heartbeat for direct iOS Wi-Fi access.

Requires pymobiledevice3. Never prints or creates pairing records. This fallback
is useful when Bonjour/usbmux discovery is missing but lockdownd is reachable.
"""
import argparse
import io
import json
import plistlib
import socket
import threading
import time
import zipfile
from contextlib import contextmanager
from pathlib import Path

from pymobiledevice3.lockdown import create_using_tcp
from pymobiledevice3.pair_records import get_usbmux_pairing_record
from pymobiledevice3.services.afc import AfcService
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.tcp_forwarder import LockdownTcpForwarder


@contextmanager
def connected(host, udid):
    record = get_usbmux_pairing_record(udid)
    if not record:
        raise RuntimeError("No existing pairing record for this device")
    lockdown = create_using_tcp(host, pair_record=record, autopair=False)
    heartbeat = None
    stopped = threading.Event()
    worker = None
    try:
        if lockdown.all_values.get("UniqueDeviceID") != udid:
            raise RuntimeError("The host is not the requested device")
        heartbeat = lockdown.start_lockdown_service("com.apple.mobile.heartbeat")
        heartbeat.recv_plist()
        heartbeat.send_plist({"Command": "Polo"})

        def keep_alive():
            try:
                while not stopped.is_set():
                    heartbeat.recv_plist()
                    if not stopped.is_set():
                        heartbeat.send_plist({"Command": "Polo"})
            except Exception:
                stopped.set()

        worker = threading.Thread(target=keep_alive, daemon=True)
        worker.start()
        yield lockdown
    finally:
        stopped.set()
        if heartbeat:
            heartbeat.close()
        if worker:
            worker.join(timeout=1)
        lockdown.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--bundle", default="com.hadashboard.app")
    commands = parser.add_subparsers(dest="command", required=True)
    diagnostics = commands.add_parser("diagnostics")
    diagnostics.add_argument("--output", type=Path, required=True)
    commands.add_parser("info")
    install = commands.add_parser("upgrade")
    install.add_argument("app", type=Path)
    debug = commands.add_parser("debugserver")
    debug.add_argument("--port", type=int, default=12389)
    args = parser.parse_args()
    socket.setdefaulttimeout(30)
    with connected(args.host, args.udid) as lockdown:
        if args.command == "diagnostics":
            with HouseArrestService(lockdown, args.bundle) as files:
                # AFC can stat one generation and open the next while the app
                # replaces its periodic snapshot. Never publish a partial read.
                for attempt in range(3):
                    raw = files.get_file_contents("/Documents/ble-proxy-diagnostics.json")
                    try:
                        snapshot = json.loads(raw)
                        break
                    except ValueError:
                        if attempt == 2:
                            raise
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(raw)
            print(json.dumps({"build": snapshot.get("app_build"),
                              "age_seconds": round(time.time() - snapshot["time"], 1),
                              "status": snapshot.get("status"),
                              "matches": snapshot.get("identity_matches")}))
        elif args.command in ("info", "upgrade"):
            if args.command == "upgrade":
                info = plistlib.loads((args.app / "Info.plist").read_bytes())
                if info.get("CFBundleIdentifier") != args.bundle:
                    raise RuntimeError("Artifact bundle does not match the requested app")
                payload = io.BytesIO()
                with zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED) as archive:
                    for path in sorted(args.app.rglob("*")):
                        if path.is_symlink():
                            raise RuntimeError("Symlinks require a prepackaged artifact")
                        if path.is_file():
                            archive.write(path, str(Path("Payload") / args.app.name /
                                                    path.relative_to(args.app)))
                with AfcService(lockdown) as files:
                    files.makedirs("/PublicStaging")
                with InstallationProxyService(lockdown) as installer:
                    installer.install_from_bytes(payload.getvalue(), cmd="Upgrade")
            with InstallationProxyService(lockdown) as installer:
                result = installer.lookup({"BundleIDs": [args.bundle], "ReturnAttributes": [
                    "CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString",
                    "CFBundleExecutable", "Path"]})
            print(json.dumps(result))
        else:
            print(f"Debugserver: connect://127.0.0.1:{args.port}", flush=True)
            LockdownTcpForwarder(lockdown, args.port,
                                 "com.apple.debugserver.DVTSecureSocketProxy").start(
                                     address="127.0.0.1")


if __name__ == "__main__":
    main()
