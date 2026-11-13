#!/usr/bin/env node
// Uploads the packaged extension to the Chrome Web Store and submits it for review,
// with the Chrome Web Store API (v2) directly, so the credentials only ever go to
// Google. Run by .github/workflows/publish-extension.yml:
//   node publish-chrome.mjs [dist/web-extension.zip]
// Env: CWS_CLIENT_ID, CWS_CLIENT_SECRET, CWS_REFRESH_TOKEN, CWS_PUBLISHER_ID,
// CWS_EXTENSION_ID (see STORE.md, "Automated publishing").

import { readFileSync } from 'node:fs'

const API = 'https://chromewebstore.googleapis.com'
const zip = process.argv[2] || 'dist/web-extension.zip'

function fail(message) {
  console.error(`error: ${message}`)
  process.exit(1)
}

function env(name) {
  return process.env[name] || fail(`${name} is not set`)
}

async function call(what, url, init = {}) {
  const res = await fetch(url, init)
  const body = await res.json().catch(() => ({}))
  if (!res.ok) fail(`${what}: HTTP ${res.status} ${body.error?.message || JSON.stringify(body)}`)
  return body
}

const item = `publishers/${env('CWS_PUBLISHER_ID')}/items/${env('CWS_EXTENSION_ID')}`

const { access_token: token } = await call('getting an access token', 'https://oauth2.googleapis.com/token', {
  method: 'POST',
  body: new URLSearchParams({
    client_id: env('CWS_CLIENT_ID'),
    client_secret: env('CWS_CLIENT_SECRET'),
    refresh_token: env('CWS_REFRESH_TOKEN'),
    grant_type: 'refresh_token',
  }),
})
const auth = { Authorization: `Bearer ${token}` }

const upload = await call('uploading', `${API}/upload/v2/${item}:upload`, {
  method: 'POST',
  headers: { ...auth, 'X-Goog-Upload-Protocol': 'raw', 'X-Goog-Upload-File-Name': 'extension.zip' },
  body: readFileSync(zip),
})
let state = upload.uploadState
for (let waited = 0; state === 'IN_PROGRESS' && waited < 300; waited += 5) {
  await new Promise((resolve) => setTimeout(resolve, 5000))
  state = (await call('checking the upload', `${API}/v2/${item}:fetchStatus`, { headers: auth })).lastAsyncUploadState
}
if (state !== 'SUCCEEDED') fail(`the upload ended ${state}: ${JSON.stringify(upload)}`)
console.log(`Uploaded version ${upload.crxVersion}`)

await call('submitting for review', `${API}/v2/${item}:publish`, {
  method: 'POST',
  headers: { ...auth, 'Content-Type': 'application/json' },
  body: JSON.stringify({ publishType: 'DEFAULT_PUBLISH' }),
})
console.log('Submitted for review: it goes live once Google approves it.')
