#!/usr/bin/env node
// Packages the runtime files into a distributable zip for Chrome (Web Store) and
// Firefox (AMO). One zip serves both — the Firefox id lives in manifest.json's
// browser_specific_settings, which Chrome and Safari ignore. The dev-only `key`
// (pins the unpacked Chrome id) is stripped: the Web Store rejects it and assigns its
// own id. Run: node package.mjs

import { execFileSync } from 'node:child_process'
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const dist = join(here, 'dist')
const stage = join(dist, 'stage')
const out = join(dist, 'web-extension.zip')

const files = ['enhance.css', 'layout-engine.js', 'call-bridge.js', 'background.js', 'popup.html', 'popup.js', 'icons', 'providers']

rmSync(stage, { recursive: true, force: true })
rmSync(out, { force: true })
mkdirSync(stage, { recursive: true })

for (const f of files) cpSync(join(here, f), join(stage, f), { recursive: true })
const manifest = JSON.parse(readFileSync(join(here, 'manifest.json'), 'utf8'))
delete manifest.key
writeFileSync(join(stage, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n')

// -r: recurse into folders; -X: no extra file attributes. Run from the stage so paths
// are relative to the extension root.
try {
  execFileSync('zip', ['-rX', out, 'manifest.json', ...files], { cwd: stage, stdio: 'inherit' })
} finally {
  rmSync(stage, { recursive: true, force: true })
}

console.log('Wrote dist/web-extension.zip (manifest.json without key, %s)', files.join(', '))
