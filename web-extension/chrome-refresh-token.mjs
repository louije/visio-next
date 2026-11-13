#!/usr/bin/env node
// Gets the Chrome Web Store refresh token publish-chrome.mjs needs, talking only to
// Google: opens Google's sign-in page, catches the code on a local port, exchanges it
// at once, and prints the refresh token on stdout (messages go to stderr).
// Env: CWS_CLIENT_ID, CWS_CLIENT_SECRET (an OAuth client of type "Desktop app").
//   TOKEN=$(node chrome-refresh-token.mjs) && printf %s "$TOKEN" | gh secret set CWS_REFRESH_TOKEN

import { execFile } from 'node:child_process'
import { createServer } from 'node:http'

function fail(message) {
  console.error(`error: ${message}`)
  process.exit(1)
}

const clientId = process.env.CWS_CLIENT_ID || fail('CWS_CLIENT_ID is not set')
const clientSecret = process.env.CWS_CLIENT_SECRET || fail('CWS_CLIENT_SECRET is not set')
let redirectUri

const server = createServer(async (req, res) => {
  const query = new URL(req.url, redirectUri).searchParams
  const code = query.get('code'), error = query.get('error')
  if (!code && !error) return res.writeHead(404).end() // e.g. the tab's favicon
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
  res.end(code ? 'Got it, you can close this tab.' : `Google said: ${error}`)
  server.close()
  if (!code) fail(`sign-in refused: ${error}`)

  const answer = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: redirectUri,
      client_id: clientId, client_secret: clientSecret,
    }),
  }).then((r) => r.json())
  if (!answer.refresh_token) fail(`no refresh token: ${JSON.stringify(answer)}`)
  process.stdout.write(answer.refresh_token + '\n')
})

// Desktop app clients accept any loopback port.
server.listen(0, '127.0.0.1', () => {
  redirectUri = `http://127.0.0.1:${server.address().port}`
  const signIn = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
    client_id: clientId, redirect_uri: redirectUri, response_type: 'code',
    scope: 'https://www.googleapis.com/auth/chromewebstore', access_type: 'offline', prompt: 'consent',
  })
  console.error(`Sign in as the account that owns the extension. If no browser opens, go to:\n${signIn}`)
  execFile('open', [signIn], () => {})
})
