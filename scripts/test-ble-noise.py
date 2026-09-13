#!/usr/bin/env python3
"""Native Noise interoperability and negative controls; no radio acceptance.

Build libbleproto.dylib with the production .m/.c files and run this script using
build/ble-proxy-venv/bin/python. All keys are freshly generated test data.
"""
import ctypes
import asyncio
import base64
import os
import socket
import threading
import time
from pathlib import Path
import unittest

import objc
from Foundation import NSData, NSDate, NSObject, NSRunLoop, NSDefaultRunLoopMode
from noise.connection import NoiseConnection
from aioesphomeapi import APIClient
from aioesphomeapi.core import InvalidEncryptionKeyAPIError, RequiresEncryptionAPIError
from aioesphomeapi.api_pb2 import HelloResponse

ROOT = Path(__file__).resolve().parents[1]
ctypes.CDLL(str(ROOT / "build/ble-proxy-receipts/libbleproto.dylib"))
Session = objc.lookUpClass("HABLENoiseSession")
Server = objc.lookUpClass("HABLEAPIServer")


class NativeServerDelegate(NSObject):
    @objc.typedSelector(b"v@:@Q@@")
    def bleServer_receivedType_data_connection_(self, server, type_, payload, connection):
        self.messages.append(type_)
        if type_ == 1:
            reply = HelloResponse(api_version_major=1, api_version_minor=12, name="native-test").SerializeToString()
            server.sendType_data_to_(2, data(reply), connection)
        elif type_ in (3, 5, 7):
            server.sendType_data_to_(type_ + 1, data(b""), connection)

    @objc.typedSelector(b"v@:@@")
    def bleServer_closedConnection_(self, server, connection):
        # The server has removed its owning reference before this callback.
        # Access the object to exercise its lifetime on the close path.
        self.closed_states.append(bool(connection.authenticated()))


def data(value):
    return NSData.dataWithBytes_length_(value, len(value))


def peers(wrong_key=False):
    key = os.urandom(32)
    native = Session.alloc().initWithKey_(data(key))
    client = NoiseConnection.from_name(b"Noise_NNpsk0_25519_ChaChaPoly_SHA256")
    client.set_as_initiator()
    client.set_psks(os.urandom(32) if wrong_key else key)
    client.set_prologue(b"NoiseAPIInit\x00\x00")
    client.start_handshake()
    request = bytes(client.write_message())
    return native, client, request


class NoiseTests(unittest.TestCase):
    def test_upstream_bidirectional_transport(self):
        native, client, request = peers()
        reply = native.respondToHandshake_(data(request))
        self.assertIsNotNone(reply)
        client.read_message(bytes(reply))
        for payload in [b"", b"hello", bytes(range(256)), os.urandom(16388)]:
            self.assertEqual(bytes(native.decrypt_(data(bytes(client.encrypt(payload))))), payload)
            self.assertEqual(bytes(client.decrypt(bytes(native.encrypt_(data(payload))))), payload)

    def test_wrong_key(self):
        native, client, request = peers(wrong_key=True)
        self.assertIsNone(native.respondToHandshake_(data(request)))
        self.assertIsNone(native.encrypt_(data(b"unauthenticated")))

    def test_corrupt_handshake_and_retry(self):
        native, client, request = peers()
        damaged = request[:-1] + bytes([request[-1] ^ 1])
        self.assertIsNone(native.respondToHandshake_(data(damaged)))
        self.assertIsNone(native.respondToHandshake_(data(request)))

    def test_tampering_invalidates_session(self):
        native, client, request = peers()
        client.read_message(bytes(native.respondToHandshake_(data(request))))
        frame = bytes(client.encrypt(b"command"))
        self.assertIsNone(native.decrypt_(data(frame[:-1] + bytes([frame[-1] ^ 1]))))
        self.assertIsNone(native.decrypt_(data(bytes(client.encrypt(b"next")))))
        self.assertIsNone(native.encrypt_(data(b"reply")))

    def test_replay_rejected(self):
        native, client, request = peers()
        client.read_message(bytes(native.respondToHandshake_(data(request))))
        frame = bytes(client.encrypt(b"command"))
        self.assertEqual(bytes(native.decrypt_(data(frame))), b"command")
        self.assertIsNone(native.decrypt_(data(frame)))

    def test_bounds(self):
        self.assertIsNone(Session.alloc().initWithKey_(data(b"short")))
        native, client, request = peers()
        client.read_message(bytes(native.respondToHandshake_(data(request))))
        self.assertIsNone(native.encrypt_(data(bytes(16389))))
        self.assertIsNone(native.decrypt_(data(bytes(16405))))


class NativeTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # aioesphomeapi caches its timezone task. Keep one client event loop,
        # as Home Assistant does, while Cocoa callbacks run on the main thread.
        cls.client_loop = asyncio.new_event_loop()
        cls.client_thread = threading.Thread(target=cls.client_loop.run_forever, daemon=True)
        cls.client_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.client_loop.call_soon_threadsafe(cls.client_loop.stop)
        cls.client_thread.join(timeout=2)
        cls.client_loop.close()

    def setUp(self):
        self.key = os.urandom(32)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        self.delegate = NativeServerDelegate.alloc().init()
        self.delegate.messages = []
        self.delegate.closed_states = []
        self.server = Server.alloc().initWithName_address_key_("native-test", "02:00:00:00:00:01", data(self.key))
        self.server.setDelegate_(self.delegate)
        started = self.server.startWithHost_port_error_("127.0.0.1", self.port, None)
        self.assertTrue(started[0] if isinstance(started, tuple) else started)

    def tearDown(self):
        self.server.stop()

    def run_client(self, work):
        future = asyncio.run_coroutine_threadsafe(work(), self.client_loop)
        deadline = time.monotonic() + 10
        while not future.done() and time.monotonic() < deadline:
            NSRunLoop.currentRunLoop().runMode_beforeDate_(NSDefaultRunLoopMode, NSDate.dateWithTimeIntervalSinceNow_(0.01))
        self.assertTrue(future.done(), "Native transport/client test timed out")
        return future.result()

    def test_upstream_api_client_connects(self):
        async def work():
            client = APIClient("127.0.0.1", self.port, noise_psk=base64.b64encode(self.key).decode())
            await client.connect()
            await client.disconnect()

        self.run_client(work)
        self.assertIn(1, self.delegate.messages)

    def test_wrong_key_classified_for_ha_setup_probe(self):
        async def work():
            client = APIClient("127.0.0.1", self.port, noise_psk=base64.b64encode(os.urandom(32)).decode())
            try:
                with self.assertRaises(InvalidEncryptionKeyAPIError):
                    await client.connect()
            finally:
                await client.disconnect(force=True)

        self.run_client(work)
        self.assertEqual(self.delegate.messages, [])

    def test_plaintext_rejected_before_application_commands(self):
        async def work():
            client = APIClient("127.0.0.1", self.port)
            try:
                with self.assertRaises(RequiresEncryptionAPIError):
                    await client.connect()
            finally:
                await client.disconnect(force=True)

        self.run_client(work)
        self.assertEqual(self.delegate.messages, [])

    def test_oversized_frame_closes_connection(self):
        async def work():
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            writer.write(b"\x01\xff\xff")
            await writer.drain()
            self.assertEqual(await asyncio.wait_for(reader.read(1), 2), b"")
            writer.close()
            await writer.wait_closed()

        self.run_client(work)
        self.assertEqual(self.delegate.messages, [])


if __name__ == "__main__":
    unittest.main()
