"""QuickLink opt-in, bounded-memory relay. Files are never written to storage.

Run ONE worker: routing state is deliberately ephemeral and process-local.
TLS termination and sender credentials are mandatory in production.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import os
import secrets
import time
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse, Response
from pydantic import BaseModel, Field, field_validator, model_validator

CHUNK = 65536
MAX_SHARES = 256
IDLE_TIMEOUT = 60


def fail(status: int, message: str):
    raise HTTPException(status, message)


class FileSpec(BaseModel):
    name: str = Field(min_length=1, max_length=240)
    size: int = Field(ge=0, le=10 * 1024**3)
    sha256: str = Field(pattern=r'^[a-f0-9]{64}$')

    @model_validator(mode='after')
    def empty_checksum(self):
        if self.size == 0 and self.sha256 != hashlib.sha256(b'').hexdigest():
            raise ValueError('Empty file checksum must match empty content')
        return self

    @field_validator('name')
    @classmethod
    def safe_name(cls, value):
        if value in ('.', '..') or any(c in value for c in '/\\') or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError('A plain filename without control characters is required')
        return value


class CreateShare(BaseModel):
    files: list[FileSpec] = Field(min_length=1, max_length=100)
    expires_in: int = Field(default=900, ge=60, le=86400)
    # A download means one attempt to download one file, including failed attempts.
    download_limit: int = Field(default=10, ge=1, le=100)
    pin: str = Field(default='', max_length=12)

    @field_validator('pin')
    @classmethod
    def valid_pin(cls, value):
        if value and (not value.isascii() or not value.isdigit() or len(value) < 6):
            raise ValueError('PIN must contain 6–12 ASCII digits')
        return value


class Access(BaseModel):
    key: str = Field(max_length=128)
    pin: str = Field(default='', max_length=12)


@dataclass
class Transfer:
    file_index: int
    queue: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=2))
    claimed: bool = False
    closed: asyncio.Event = field(default_factory=asyncio.Event)
    created: float = field(default_factory=time.monotonic)


@dataclass
class Share:
    files: list[FileSpec]
    expires: float
    key_hash: bytes
    owner_hash: bytes
    salt: bytes
    pin_hash: bytes | None
    remaining: int
    sessions: dict[str, float] = field(default_factory=dict)
    requests: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=1))
    active: dict[str, Transfer] = field(default_factory=dict)
    failures: int = 0
    locked_until: float = 0


shares: dict[str, Share] = {}


def digest(value: str) -> bytes:
    return hashlib.sha256(value.encode()).digest()


def pin_digest(value: str, salt: bytes) -> bytes:
    return hashlib.scrypt(value.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)


def get_share(share_id: str) -> Share:
    share = shares.get(share_id)
    if share is None or share.expires <= time.time():
        fail(410, 'Share expired, revoked, or unavailable')
    return share


def bearer(request: Request) -> str:
    value = request.headers.get('authorization', '')
    if not value.startswith('Bearer ') or len(value) > 256:
        fail(401, 'Authentication required')
    return value[7:]


def owner(request: Request, share: Share):
    if not hmac.compare_digest(digest(bearer(request)), share.owner_hash):
        fail(403, 'Invalid sender credential')


def receiver(request: Request, share: Share):
    now = time.time()
    share.sessions = {k: v for k, v in share.sessions.items() if v > now}
    if share.sessions.get(digest(bearer(request)).hex(), 0) <= now:
        fail(403, 'Download session expired or invalid')


def close_share(share: Share):
    for transfer in share.active.values():
        transfer.closed.set()


async def cleanup():
    while True:
        await asyncio.sleep(5)
        now = time.time()
        for key, share in list(shares.items()):
            if share.expires <= now:
                close_share(share)
                shares.pop(key, None)
            else:
                share.sessions = {k: v for k, v in share.sessions.items() if v > now}


@asynccontextmanager
async def lifespan(app):
    token = os.environ.get('QUICKLINK_SENDER_TOKEN', '')
    if len(token) < 32:
        raise RuntimeError('Set QUICKLINK_SENDER_TOKEN to a random credential of at least 32 characters')
    task = asyncio.create_task(cleanup())
    yield
    task.cancel()
    with suppress(asyncio.CancelledError):
        await task
    for share in shares.values():
        close_share(share)
    shares.clear()


app = FastAPI(title='QuickDrop QuickLink', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


@app.middleware('http')
async def privacy_headers(request: Request, call_next):
    # Reject unexpected public hosts at the TLS reverse proxy; no CORS is enabled.
    if request.headers.get('content-length', '').isdigit():
        if not request.url.path.endswith('/upload') and int(request.headers['content-length']) > 65536:
            return JSONResponse({'detail': 'Request too large'}, status_code=413)
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
    return response


@app.get('/healthz')
async def health():
    return {'status': 'ok', 'storage': 'none'}


@app.get('/s/{share_id}')
async def landing(share_id: str):
    # Do not reveal existence or metadata until the link capability is authenticated.
    return FileResponse(Path(__file__).parent / 'static/index.html')


@app.get('/assets/{name}')
async def asset(name: str):
    if name not in ('app.js', 'style.css'):
        fail(404, 'Not found')
    return FileResponse(Path(__file__).parent / 'static' / name)


@app.post('/api/shares', status_code=201)
async def create(body: CreateShare, request: Request):
    configured = os.environ.get('QUICKLINK_SENDER_TOKEN', '')
    if len(configured) < 32 or not hmac.compare_digest(digest(bearer(request)), digest(configured)):
        fail(403, 'Invalid sender credential')
    if len(shares) >= MAX_SHARES:
        fail(503, 'Relay capacity reached; retry later')
    sid, key, owner_key = (secrets.token_urlsafe(32) for _ in range(3))
    salt = secrets.token_bytes(16)
    hashed_pin = await asyncio.to_thread(pin_digest, body.pin, salt) if body.pin else None
    # Recheck capacity after awaiting the expensive PIN derivation.
    if len(shares) >= MAX_SHARES:
        fail(503, 'Relay capacity reached')
    expires = time.time() + body.expires_in
    shares[sid] = Share(body.files, expires, digest(key), digest(owner_key), salt, hashed_pin, body.download_limit)
    return {'id': sid, 'key': key, 'owner_token': owner_key, 'expires_at': expires}


@app.post('/api/shares/{sid}/access')
async def access(sid: str, body: Access):
    share = get_share(sid)
    if not hmac.compare_digest(digest(body.key), share.key_hash):
        fail(403, 'Invalid share key or PIN')
    if share.locked_until > time.time():
        fail(429, 'Too many attempts; retry after 15 minutes')
    # Increment before await so parallel PIN requests cannot bypass the limit.
    share.failures += 1
    if share.failures >= 5:
        share.locked_until = time.time() + 900
    if share.pin_hash is not None:
        candidate = await asyncio.to_thread(pin_digest, body.pin, share.salt)
        if not hmac.compare_digest(candidate, share.pin_hash):
            fail(403, 'Invalid share key or PIN')
    share.failures = 0
    share.locked_until = 0
    if share.remaining <= 0:
        fail(410, 'Download limit reached')
    if len(share.sessions) >= 128:
        fail(429, 'Too many active download sessions')
    token = secrets.token_urlsafe(32)
    share.sessions[digest(token).hex()] = min(share.expires, time.time() + 600)
    return {'token': token, 'files': [f.model_dump() for f in share.files], 'expires_at': share.expires, 'remaining': share.remaining}


@app.get('/api/shares/{sid}/next')
async def next_transfer(sid: str, request: Request):
    share = get_share(sid)
    owner(request, share)
    try:
        tid = await asyncio.wait_for(share.requests.get(), timeout=20)
    except asyncio.TimeoutError:
        return JSONResponse({}, status_code=204)
    transfer = share.active.get(tid)
    if transfer is None or transfer.closed.is_set():
        return JSONResponse({}, status_code=204)
    return {'transfer_id': tid, 'file_index': transfer.file_index}


@app.get('/api/shares/{sid}/files/{index}')
async def download(sid: str, index: int, request: Request):
    share = get_share(sid)
    receiver(request, share)
    if index < 0 or index >= len(share.files):
        fail(404, 'File not found')
    if share.remaining <= 0:
        fail(410, 'Download limit reached')
    if share.active:
        fail(409, 'A download is active; retry when it finishes')
    spec = share.files[index]
    if spec.size == 0:
        share.remaining -= 1
        return Response(content=b'', media_type='application/octet-stream', headers={
            'Content-Disposition': "attachment; filename*=UTF-8''" + quote(spec.name, safe=''),
            'X-QuickDrop-SHA256': spec.sha256,
        })
    tid = secrets.token_urlsafe(24)
    transfer = Transfer(index)
    share.active[tid] = transfer
    share.remaining -= 1
    # No await between reservation and insertion: one active transfer per share.
    while not share.requests.empty():
        share.requests.get_nowait()
    share.requests.put_nowait(tid)

    async def stream():
        try:
            while True:
                if transfer.closed.is_set() or share.expires <= time.time():
                    raise RuntimeError('Transfer revoked or expired')
                take = asyncio.create_task(transfer.queue.get())
                closed = asyncio.create_task(transfer.closed.wait())
                try:
                    done, _ = await asyncio.wait({take, closed}, timeout=IDLE_TIMEOUT, return_when=asyncio.FIRST_COMPLETED)
                    if not done or closed in done:
                        raise RuntimeError('Transfer interrupted')
                    data = await take
                finally:
                    for task in (take, closed):
                        if not task.done():
                            task.cancel()
                    await asyncio.gather(take, closed, return_exceptions=True)
                if isinstance(data, Exception):
                    raise RuntimeError('Sender interrupted or integrity check failed')
                if data is None:
                    break
                yield data
        finally:
            transfer.closed.set()
            share.active.pop(tid, None)

    return StreamingResponse(stream(), media_type='application/octet-stream', headers={
        'Content-Length': str(spec.size),
        'Content-Disposition': "attachment; filename*=UTF-8''" + quote(spec.name, safe=''),
        'X-QuickDrop-SHA256': spec.sha256,
    })


async def put_chunk(transfer: Transfer, data):
    if transfer.closed.is_set():
        fail(409, 'Receiver disconnected')
    put = asyncio.create_task(transfer.queue.put(data))
    closed = asyncio.create_task(transfer.closed.wait())
    try:
        done, _ = await asyncio.wait({put, closed}, timeout=IDLE_TIMEOUT, return_when=asyncio.FIRST_COMPLETED)
        if not done or closed in done:
            fail(409, 'Receiver disconnected or timed out')
        await put
    finally:
        for task in (put, closed):
            if not task.done():
                task.cancel()
        await asyncio.gather(put, closed, return_exceptions=True)


@app.post('/api/shares/{sid}/transfers/{tid}/upload')
async def upload(sid: str, tid: str, request: Request):
    share = get_share(sid)
    owner(request, share)
    transfer = share.active.get(tid)
    if transfer is None or transfer.claimed or transfer.closed.is_set():
        fail(409, 'Download request unavailable or already claimed')
    transfer.claimed = True
    spec = share.files[transfer.file_index]
    if request.headers.get('content-length') != str(spec.size):
        transfer.closed.set()
        fail(400, 'File size does not match')
    count, checksum, pending = 0, hashlib.sha256(), b''
    try:
        async for data in request.stream():
            if transfer.closed.is_set() or share.expires <= time.time():
                fail(410, 'Transfer expired or receiver disconnected')
            count += len(data)
            if count > spec.size:
                fail(400, 'File size exceeded')
            checksum.update(data)
            for offset in range(0, len(data), CHUNK):
                if pending:
                    await put_chunk(transfer, pending)
                pending = data[offset:offset + CHUNK]
        if count != spec.size or not hmac.compare_digest(checksum.hexdigest(), spec.sha256):
            fail(400, 'File size or SHA-256 mismatch')
        # Withhold final bytes until integrity is confirmed. A corrupt stream is truncated.
        if pending:
            await put_chunk(transfer, pending)
        await put_chunk(transfer, None)
        return {'status': 'uploaded', 'bytes': count}
    except BaseException:
        transfer.closed.set()
        # Wake a receiver blocked on queue.get without blocking this error path.
        with suppress(asyncio.QueueFull):
            transfer.queue.put_nowait(RuntimeError('Upload interrupted'))
        raise


@app.delete('/api/shares/{sid}', status_code=204)
async def revoke(sid: str, request: Request):
    share = get_share(sid)
    owner(request, share)
    close_share(share)
    shares.pop(sid, None)
