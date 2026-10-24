"""Send a synthetic fixture to a running local app over certificate-pinned mTLS.

Requires Python cryptography. Only use with a test app profile, not a user's
production identity. The app's PUBLIC certificate is trusted, never its private
key. Approve the receiving prompt in the running application. No tokens, key
material or file contents are printed. The uniquely named fixture is removed
from the specified destination after verification.
"""
import argparse
import datetime
import hashlib
import http.client
import json
import secrets
import ssl
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--settings', required=True, type=Path)
    parser.add_argument('--receive-directory', required=True, type=Path)
    parser.add_argument('--port', type=int, default=53317)
    args = parser.parse_args()
    prefs = json.loads(args.settings.read_text())
    identity = json.loads(prefs['flutter.ls_security_context'])
    public_cert = identity['certificate']
    expected_pin = hashlib.sha256(x509.load_pem_x509_certificate(public_cert.encode()).public_bytes(serialization.Encoding.DER)).digest()
    del identity, prefs
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'QuickDrop readiness fixture')])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=1)).not_valid_after(now+datetime.timedelta(hours=1)).sign(key, hashes.SHA256())
    fingerprint = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest().upper()
    data = bytes(range(256)) * 4096
    checksum = hashlib.sha256(data).hexdigest()
    file_id = secrets.token_hex(16)
    filename = f'quickdrop-readiness-{file_id}.bin'
    output = args.receive_directory / filename
    if output.exists():
        raise RuntimeError('The synthetic fixture path must not already exist')
    with tempfile.TemporaryDirectory(prefix='quickdrop-client-') as temp:
        cert_path, key_path = Path(temp)/'cert.pem', Path(temp)/'key.pem'
        cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        key_path.chmod(0o600)
        context = ssl.create_default_context(cadata=public_cert)
        # LocalSend certs deliberately have no DNS SAN. Their identity is the
        # trusted certificate plus the exact SHA-256 pin, not a hostname.
        context.check_hostname = False
        context.load_cert_chain(cert_path, key_path)

        def request(method, path, body=None, binary=False):
            connection = http.client.HTTPSConnection('127.0.0.1', args.port, context=context, timeout=90)
            connection.connect()
            if hashlib.sha256(connection.sock.getpeercert(binary_form=True)).digest() != expected_pin:
                connection.close()
                raise RuntimeError('Application certificate identity changed')
            try:
                headers = {'Content-Type':'application/octet-stream' if binary else 'application/json'}
                payload = body if binary else json.dumps(body).encode() if body is not None else None
                connection.request(method, path, payload, headers)
                response = connection.getresponse()
                value = response.read()
                if response.status != 200:
                    raise RuntimeError(f'Test operation failed with HTTP {response.status}')
                return json.loads(value) if value else None
            finally:
                connection.close()

        info = request('GET', '/api/localsend/v2/info')
        assert info['alias']
        print('Verified running app over mutual TLS. Approve the synthetic file request in QuickDrop.', flush=True)
        prepared = request('POST', '/api/localsend/v2/prepare-upload', {
            'info': {'alias':'QuickDrop readiness test', 'version':'2.2', 'deviceModel':'Synthetic test sender', 'deviceType':'desktop',
                     'fingerprint':fingerprint, 'port':53318, 'protocol':'https', 'download':False},
            'files': {file_id:{'id':file_id, 'fileName':filename, 'size':len(data), 'fileType':'application/octet-stream', 'sha256':checksum}},
        })
        query = urlencode({'sessionId':prepared['sessionId'], 'fileId':file_id, 'token':prepared['files'][file_id]})
        request('POST', '/api/localsend/v2/upload?'+query, data, binary=True)
        deadline = time.monotonic()+10
        while not output.exists() and time.monotonic()<deadline:
            time.sleep(.05)
        assert output.exists(), 'The accepted fixture must be saved to the chosen test directory'
        assert output.stat().st_size == len(data)
        assert hashlib.sha256(output.read_bytes()).hexdigest() == checksum
        output.unlink()
        print('PASS: accepted 1 MiB through the actual Flutter app; received bytes and SHA-256 match; fixture removed.', flush=True)


if __name__ == '__main__':
    main()
