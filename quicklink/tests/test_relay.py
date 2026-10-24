"""Real HTTP integration tests: no external server, account or file storage."""
import concurrent.futures
import hashlib
import os
import secrets
import socket
import threading
import time
import unittest

import httpx
import uvicorn
from quicklink.service import app, shares


class RelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.credential = secrets.token_urlsafe(40)
        os.environ['QUICKLINK_SENDER_TOKEN'] = cls.credential
        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        cls.origin = f'http://127.0.0.1:{sock.getsockname()[1]}'
        cls.server = uvicorn.Server(uvicorn.Config(app, log_level='critical', access_log=False))
        cls.thread = threading.Thread(target=cls.server.run, kwargs={'sockets': [sock]}, daemon=True)
        cls.thread.start()
        deadline = time.monotonic() + 10
        while not cls.server.started:
            if time.monotonic() > deadline:
                raise RuntimeError('Test server failed to start')
            time.sleep(.02)

    @classmethod
    def tearDownClass(cls):
        cls.server.should_exit = True
        cls.thread.join(timeout=10)

    def setUp(self):
        self.client = httpx.Client(base_url=self.origin, trust_env=False, timeout=10)
        self.master = {'Authorization': f'Bearer {self.credential}'}
        self.created = []

    def tearDown(self):
        for sid, headers in self.created:
            self.client.delete(f'/api/shares/{sid}', headers=headers)
        self.client.close()

    def create(self, data=b'QuickDrop', **overrides):
        payload = {'files': [{'name': 'sample.bin', 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}], **overrides}
        response = self.client.post('/api/shares', json=payload, headers=self.master)
        self.assertEqual(response.status_code, 201, response.text)
        body = response.json()
        owner = {'Authorization': f"Bearer {body['owner_token']}"}
        self.created.append((body['id'], owner))
        return body, owner

    def access(self, share, pin=''):
        response = self.client.post(f"/api/shares/{share['id']}/access", json={'key': share['key'], 'pin': pin})
        self.assertEqual(response.status_code, 200, response.text)
        return {'Authorization': f"Bearer {response.json()['token']}"}

    def transfer(self, share, owner, receiver, data):
        sid = share['id']
        with concurrent.futures.ThreadPoolExecutor() as pool:
            future = pool.submit(self.client.get, f'/api/shares/{sid}/files/0', headers=receiver)
            pending = self.client.get(f'/api/shares/{sid}/next', headers=owner)
            self.assertEqual(pending.status_code, 200, pending.text)
            tid = pending.json()['transfer_id']
            result = self.client.post(f'/api/shares/{sid}/transfers/{tid}/upload', headers=owner, content=data)
            return result, future

    def test_authentication_and_metadata_privacy(self):
        self.assertEqual(self.client.post('/api/shares', json={'files': []}).status_code, 422)
        payload = {'files': [{'name': 'secret.txt', 'size': 1, 'sha256': '0'*64}]}
        self.assertEqual(self.client.post('/api/shares', json=payload).status_code, 401)
        share, owner = self.create()
        sid = share['id']
        self.assertEqual(self.client.get(f'/api/shares/{sid}/next').status_code, 401)
        self.assertEqual(self.client.get(f'/api/shares/{sid}/files/0').status_code, 401)
        response = self.client.post(f'/api/shares/{sid}/access', json={'key': 'wrong'})
        self.assertEqual(response.status_code, 403)
        self.assertNotIn('sample.bin', response.text)
        self.assertEqual(self.client.delete(f'/api/shares/{sid}', headers=self.master).status_code, 403)

    def test_pin_and_lockout(self):
        share, _ = self.create(pin='123456')
        self.access(share, '123456')
        for _ in range(5):
            self.assertEqual(self.client.post(f"/api/shares/{share['id']}/access", json={'key': share['key'], 'pin':'000000'}).status_code, 403)
        self.assertEqual(self.client.post(f"/api/shares/{share['id']}/access", json={'key': share['key'], 'pin':'123456'}).status_code, 429)

    def test_streams_three_megabytes_with_integrity(self):
        data = os.urandom(3*1024*1024 + 53)
        share, owner = self.create(data)
        receiver = self.access(share)
        result, downloaded = self.transfer(share, owner, receiver, data)
        self.assertEqual(result.status_code, 200, result.text)
        response = downloaded.result()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, data)
        self.assertEqual(response.headers['x-quickdrop-sha256'], hashlib.sha256(data).hexdigest())
        self.assertEqual(shares[share['id']].active, {})

    def test_corruption_truncates_download(self):
        share, owner = self.create(b'correct')
        receiver = self.access(share)
        result, downloaded = self.transfer(share, owner, receiver, b'INVALID')
        self.assertEqual(result.status_code, 400)
        with self.assertRaises(httpx.RemoteProtocolError):
            downloaded.result()

    def test_download_limits_and_revocation(self):
        share, owner = self.create(download_limit=1)
        receiver = self.access(share)
        result, downloaded = self.transfer(share, owner, receiver, b'QuickDrop')
        self.assertEqual(downloaded.result().content, b'QuickDrop')
        self.assertEqual(self.client.get(f"/api/shares/{share['id']}/files/0", headers=receiver).status_code, 410)
        self.assertEqual(self.client.delete(f"/api/shares/{share['id']}", headers=owner).status_code, 204)
        self.assertEqual(self.client.post(f"/api/shares/{share['id']}/access", json={'key':share['key']}).status_code, 410)

    def test_expired_share_is_inaccessible(self):
        share, _ = self.create()
        shares[share['id']].expires = time.time() - 1
        self.assertEqual(self.client.post(f"/api/shares/{share['id']}/access", json={'key':share['key']}).status_code, 410)

    def test_unsafe_names_and_invalid_configuration(self):
        for name in ['../secret', 'folder/file', '..', 'a\\b', 'bad\r\nheader']:
            response = self.client.post('/api/shares', headers=self.master, json={'files':[{'name':name, 'size':1,'sha256':'0'*64}]})
            self.assertEqual(response.status_code, 422, name)
        for extra in [{'pin':'123'}, {'pin':'１２３４５６'}, {'expires_in':86401}, {'download_limit':0}]:
            response = self.client.post('/api/shares', headers=self.master, json={'files':[{'name':'ok','size':1,'sha256':'0'*64}], **extra})
            self.assertEqual(response.status_code, 422)

    def test_empty_file_completes(self):
        share, owner = self.create(b'')
        receiver = self.access(share)
        downloaded = self.client.get(f"/api/shares/{share['id']}/files/0", headers=receiver)
        self.assertEqual(downloaded.status_code, 200)
        self.assertEqual(downloaded.content, b'')
        self.assertEqual(shares[share['id']].active, {})

    def test_parallel_download_is_rejected_and_revoke_interrupts_active_stream(self):
        data = b'pending bytes'
        share, owner = self.create(data)
        receiver = self.access(share)
        sid = share['id']
        with concurrent.futures.ThreadPoolExecutor() as pool:
            pending = pool.submit(self.client.get, f'/api/shares/{sid}/files/0', headers=receiver)
            requested = self.client.get(f'/api/shares/{sid}/next', headers=owner)
            self.assertEqual(requested.status_code, 200)
            self.assertEqual(self.client.get(f'/api/shares/{sid}/files/0', headers=receiver).status_code, 409)
            tid = requested.json()['transfer_id']
            # A receiver credential cannot impersonate a sender.
            self.assertEqual(self.client.post(f'/api/shares/{sid}/transfers/{tid}/upload', headers=receiver, content=data).status_code, 403)
            self.client.delete(f'/api/shares/{sid}', headers=owner)
            with self.assertRaises(httpx.RemoteProtocolError):
                pending.result(timeout=5)

    def test_expired_download_session_is_rejected(self):
        share, _ = self.create()
        receiver = self.access(share)
        shares[share['id']].sessions.clear()
        self.assertEqual(self.client.get(f"/api/shares/{share['id']}/files/0", headers=receiver).status_code, 403)

    def test_browser_security_headers_and_no_injected_names(self):
        response = self.client.get('/s/unknown')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['cache-control'], 'no-store')
        self.assertEqual(response.headers['referrer-policy'], 'no-referrer')
        self.assertIn("frame-ancestors 'none'", response.headers['content-security-policy'])
        self.assertNotIn('unsafe-inline', response.headers['content-security-policy'])
        self.assertEqual(self.client.get('/assets/not-allowed').status_code, 404)


if __name__ == '__main__':
    unittest.main()
