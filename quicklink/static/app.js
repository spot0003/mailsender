'use strict';
const share = location.pathname.split('/').pop();
const key = location.hash.slice(1);
history.replaceState(null, '', location.pathname); // capability never sent in request URL
const status = document.querySelector('#status');
const form = document.querySelector('#unlock');
let session;
async function api(path, options = {}) {
  const response = await fetch(`/api/shares/${encodeURIComponent(share)}${path}`, {cache:'no-store', ...options});
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(typeof body.detail === 'string' ? body.detail : `Request failed (${response.status})`);
  }
  return response;
}
form.addEventListener('submit', async event => {
  event.preventDefault();
  const button = form.querySelector('button');
  button.disabled = true;
  try {
    if (!key) throw new Error('The complete sharing link is required. Ask the sender to send it again.');
    session = await (await api('/access', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({key, pin:document.querySelector('#pin').value})})).json();
    document.querySelector('#pin').value = '';
    form.hidden = true;
    status.textContent = `${session.remaining} file download attempts remaining. Expires ${new Date(session.expires_at*1000).toLocaleString()}.`;
    for (const [index, file] of session.files.entries()) {
      const row = document.createElement('div'); row.className = 'file';
      const name = document.createElement('strong'); name.textContent = file.name;
      const size = document.createElement('span'); size.textContent = ` · ${(file.size/1048576).toFixed(2)} MB`;
      const save = document.createElement('button'); save.textContent = 'Download';
      save.addEventListener('click', () => download(index, file, save));
      row.append(name, size, save); document.querySelector('#files').append(row);
    }
  } catch(error) {status.textContent = error.message;} finally {button.disabled = false;}
});
async function download(index, file, button) {
  button.disabled = true;
  let writer;
  try {
    // A file picker is invoked in the user gesture, before any network request.
    if ('showSaveFilePicker' in window) {
      const handle = await showSaveFilePicker({suggestedName:file.name}); writer = await handle.createWritable();
    } else if (file.size > 128*1024*1024) {
      throw new Error('For files over 128 MB use a browser with streaming Save File support (desktop Chromium).');
    }
    status.textContent = 'Connecting to sender… Keep this page open.';
    const response = await api(`/files/${index}`, {headers:{Authorization:`Bearer ${session.token}`}});
    const reader = response.body.getReader(); let received = 0; const chunks = [];
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      received += value.length;
      if (received > file.size) {await reader.cancel(); throw new Error('File size mismatch');}
      if (writer) await writer.write(value); else chunks.push(value);
      status.textContent = `${file.name}: ${Math.round(received/Math.max(1,file.size)*100)}%`;
    }
    if (received !== file.size) throw new Error('Transfer interrupted. Retry the complete file.');
    if (writer) {await writer.close(); writer = null;}
    else {
      const url = URL.createObjectURL(new Blob(chunks)); const a = document.createElement('a');
      a.href = url; a.download = file.name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 60000);
    }
    status.textContent = 'Download complete. The relay verified the sender’s SHA-256 before finishing the stream.';
  } catch(error) {
    if (writer) await writer.abort().catch(() => {});
    status.textContent = error.name === 'AbortError' ? 'Download canceled.' : `${error.message} Ask the sender to keep QuickDrop open.`;
  } finally {button.disabled = false;}
}
