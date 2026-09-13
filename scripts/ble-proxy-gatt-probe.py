#!/usr/bin/env python3
"""Use upstream aioesphomeapi against our controlled physical GATT fixture.

The proxy key comes from stdin or HA's administrator API, stays in memory, and
is never included in receipts.
Writes are allowed only after the fixture UUID and initial marker are verified.
"""
import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import sys
import time

from aioesphomeapi import APIClient
import websockets


async def key_from_home_assistant(entry):
    """Fetch only the selected proxy's key through HA's administrator API."""
    server = os.environ["HA_SERVER"].rstrip("/")
    url = server.replace("https://", "wss://", 1).replace("http://", "ws://", 1) + "/api/websocket"
    async with websockets.connect(url, open_timeout=15) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": os.environ["HA_TOKEN"]}))
        if json.loads(await ws.recv()).get("type") != "auth_ok":
            raise RuntimeError("Home Assistant authentication failed")
        await ws.send(json.dumps({"id": 1, "type": "esphome/get_encryption_key", "entry_id": entry}))
        reply = json.loads(await ws.recv())
        key = reply.get("result", {}).get("encryption_key")
        if not reply.get("success") or not isinstance(key, str):
            raise RuntimeError("Home Assistant did not provide a key for the selected proxy")
        return key


async def probe(args, key):
    fixture = json.loads(Path(args.fixture).read_text())
    address = int(args.address.replace(":", ""), 16)
    client = APIClient(args.host, 6053, noise_psk=key)
    receipt = {"time": time.time(), "host": args.host, "address": args.address,
               "fixture_service": fixture["service_uuid"], "checks": []}
    connected = False
    cancels = []

    def state(up, mtu, error):
        nonlocal connected
        connected = up
        receipt.setdefault("connection_states", []).append({"connected": up, "mtu": mtu, "error": error})

    try:
        await client.connect()
        info = await client.device_info()
        flags = info.bluetooth_proxy_feature_flags
        receipt["proxy"] = {"name": info.name, "feature_flags": flags}
        cancels.append(await client.bluetooth_device_connect(address, state, feature_flags=flags, has_cache=False, address_type=1))
        services = await client.bluetooth_gatt_get_services(address)
        characteristic = next(c for s in services.services if s.uuid.lower() == fixture["service_uuid"].lower()
                              for c in s.characteristics if c.uuid.lower() == fixture["characteristic_uuid"].lower())
        handle = characteristic.handle
        initial = bytes(await client.bluetooth_gatt_read(address, handle))
        if initial != b"HA-BLE-FIXTURE" and not initial.startswith(b"HABLE-test-"):
            raise RuntimeError("The peripheral did not return the controlled fixture marker; no write sent")
        receipt["checks"].append({"read_marker": initial.decode("ascii"), "handle": handle})
        notification = asyncio.get_running_loop().create_future()

        def changed(handle, value):
            if not notification.done():
                notification.set_result(bytes(value))

        stop_notify, cancel_notify = await client.bluetooth_gatt_start_notify(address, handle, changed)
        payload = ("HABLE-test-" + secrets.token_hex(8)).encode()
        await client.bluetooth_gatt_write(address, handle, payload, response=True)
        value = await asyncio.wait_for(notification, 15)
        assert value == payload, "Notification did not echo the test write"
        readback = bytes(await client.bluetooth_gatt_read(address, handle))
        assert readback == payload, "Readback differs from the acknowledged write"
        receipt["checks"].append({"write_read_notify": "passed", "test_payload": payload.decode()})
        await stop_notify()
        cancel_notify()
        await client.bluetooth_device_disconnect(address)
        for cancel in cancels:
            cancel()
        cancels.clear()
        cancels.append(await client.bluetooth_device_connect(address, state, feature_flags=flags, has_cache=True, address_type=1))
        cached = bytes(await client.bluetooth_gatt_read(address, handle))
        assert cached == payload, "Cached handle changed across the physical reconnect"
        receipt["checks"].append({"cached_handle_reconnect": "passed", "handle": handle})
        for iteration in range(args.stress_reconnect):
            for cancel in cancels:
                cancel()
            cancels.clear()
            # Drop the TCP client while its BLE connection is still allocated.
            # This checks server cleanup and immediate authenticated reconnect.
            await client.disconnect(force=True)
            connected = False
            client = APIClient(args.host, 6053, noise_psk=key)
            await client.connect()
            cancels.append(await client.bluetooth_device_connect(address, state, feature_flags=flags, has_cache=True, address_type=1))
            recovered = bytes(await client.bluetooth_gatt_read(address, handle))
            assert recovered == payload, "Handle or connection recovery failed after a transport drop"
            receipt["checks"].append({"transport_drop_reconnect": iteration + 1, "result": "passed"})
        receipt["success"] = True
    except Exception as error:
        receipt["success"] = False
        receipt["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        if connected:
            try:
                await client.bluetooth_device_disconnect(address)
            except Exception:
                pass
        for cancel in cancels:
            cancel()
        await client.disconnect(force=True)
        Path(args.output).write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["success"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--address", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--ha-entry", help="Read this proxy's key using HA_SERVER and HA_TOKEN, instead of stdin")
    parser.add_argument("--stress-reconnect", type=int, default=0)
    options = parser.parse_args()

    async def main():
        proxy_key = await key_from_home_assistant(options.ha_entry) if options.ha_entry else sys.stdin.read().strip()
        return await probe(options, proxy_key)

    raise SystemExit(asyncio.run(main()))
