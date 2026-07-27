#!/usr/bin/env node
/**
 * Run GUT tests headlessly. Replaces legacy Node regression suites for CI/local QA.
 * Set GODOT_BIN to your Godot 4 executable if it is not on PATH.
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const GODOT_PROJECT = path.join(ROOT, 'godot');

function findGodot() {
  if (process.env.GODOT_BIN && fs.existsSync(process.env.GODOT_BIN)) {
    return process.env.GODOT_BIN;
  }
  const candidates = [
    'godot',
    'godot4',
    'Godot',
    'Godot_v4.3-stable_win64.exe',
    'Godot_v4.4-stable_win64.exe',
    'Godot_v4.5-stable_win64.exe',
    'C:/Program Files/Godot/Godot_v4.3-stable_win64.exe',
    'C:/Program Files/Godot/Godot_v4.4-stable_win64.exe',
  ];
  for (const c of candidates) {
    const r = spawnSync(c, ['--version'], { encoding: 'utf8' });
    if (r.status === 0) return c;
  }
  return null;
}

const godot = findGodot();
if (!godot) {
  console.error('Godot 4 not found. Install Godot 4 or set GODOT_BIN to the executable path.');
  process.exit(1);
}

console.log('Running GUT via', godot);
const result = spawnSync(
  godot,
  [
    '--headless',
    '--path',
    GODOT_PROJECT,
    '-s',
    'addons/gut/gut_cmdln.gd',
    '-gconfig=.gutconfig.json',
    '-gexit',
  ],
  { stdio: 'inherit', cwd: GODOT_PROJECT },
);

process.exit(result.status ?? 1);
