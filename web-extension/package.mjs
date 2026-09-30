#!/usr/bin/env node
// Packages the runtime files into a distributable zip for Chrome (Load unpacked /
// Web Store) and Firefox (about:debugging / AMO). One zip serves both — the
// Firefox id lives in manifest.json's browser_specific_settings, which Chrome and
// Safari ignore. Run: node package.mjs

import { execFileSync } from 'node:child_process'
import { rmSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
mkdirSync(join(here, 'dist'), { recursive: true })

const out = join(here, 'dist', 'web-extension.zip')
rmSync(out, { force: true })

const files = ['manifest.json', 'enhance.css', 'layout-engine.js', 'call-bridge.js', 'background.js', 'popup.html', 'popup.js', 'icons', 'providers']
// -r: recurse into icons/; -X: no extra file attributes. Run from `here` so paths
// are relative to the extension root.
execFileSync('zip', ['-rX', out, ...files], { cwd: here, stdio: 'inherit' })

console.log('Wrote dist/web-extension.zip (%s)', files.join(', '))
