import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const launcherPath = 'Otestovat Lázeňský Commander.command';
const source = fs.readFileSync(launcherPath, 'utf8');
const functions = source.slice(source.indexOf('acquire_lock() {'), source.indexOf('wait_for_watch_connected() {'));
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'commander-lock-test-'));
let passed = 0;
function test(name, operation) {
  operation();
  passed++;
  console.log(`PASS ${name}`);
}
function run(body, lock = path.join(directory, 'lock')) {
  return spawnSync('/bin/bash', ['-c', `set -u\nfail() { echo "$1" >&2; exit 1; }\n${functions}\n${body}`], {
    env: { ...process.env, LOCK_DIR: lock }, encoding: 'utf8', timeout: 5000
  });
}
try {
  test('launcher and compatibility wrapper have valid syntax', () => {
    for (const file of [launcherPath, 'Nainstalovat stabilizační test.command']) {
      assert.equal(spawnSync('/bin/bash', ['-n', file]).status, 0);
    }
    assert.match(fs.readFileSync('Nainstalovat stabilizační test.command', 'utf8'), /exec.*Otestovat Lázeňský Commander.command/);
  });
  test('lock release is repeatable and relaunch can acquire it', () => {
    for (let i = 0; i < 2; i++) {
      const result = run('acquire_lock\nrelease_lock\nrelease_lock');
      assert.equal(result.status, 0, result.stderr);
      assert.equal(fs.existsSync(path.join(directory, 'lock')), false);
    }
  });
  test('active owner is never removed by another launcher', () => {
    const lock = path.join(directory, 'active');
    fs.mkdirSync(lock);
    fs.writeFileSync(path.join(lock, 'pid'), String(process.pid));
    const result = run('acquire_lock', lock);
    assert.equal(result.status, 1);
    assert.equal(fs.readFileSync(path.join(lock, 'pid'), 'utf8'), String(process.pid));
  });
  test('stale PID is recovered without removing evidence outside the lock', () => {
    const lock = path.join(directory, 'stale');
    fs.mkdirSync(lock);
    fs.writeFileSync(path.join(lock, 'pid'), '2147483647');
    const result = run('acquire_lock', lock);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(lock), false);
  });
  test('unverifiable owner is preserved', () => {
    const lock = path.join(directory, 'unknown');
    fs.mkdirSync(lock);
    assert.equal(run('acquire_lock', lock).status, 1);
    assert.equal(fs.existsSync(lock), true);
  });
  test('release never removes a replacement owner lock', () => {
    const lock = path.join(directory, 'replacement');
    const result = run('acquire_lock\nprintf 12345 > "$LOCK_DIR/pid"\nrelease_lock', lock);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(path.join(lock, 'pid'), 'utf8'), '12345');
  });
  test('termination exits before releasing the lock', () => {
    const lock = path.join(directory, 'terminated');
    const result = run('acquire_lock\nkill -TERM $$\nexit 99', lock);
    assert.equal(result.status, 143, result.stderr);
    assert.equal(fs.existsSync(lock), false);
  });
  test('cleanup refuses any other build directory', () => {
    const result = run('DERIVED="$LOCK_DIR"\ncleanup_test_artifacts');
    assert.equal(result.status, 1);
  });
  test('unlock wait is wall-clock bounded without nested handshake retries', () => {
    const watch = source.slice(source.indexOf('wait_for_watch_unlock() {'), source.indexOf('watch_handshake() {'));
    const iphone = source.slice(source.indexOf('wait_for_iphone_unlock() {'), source.indexOf('iphone_pid() {'));
    for (const body of [watch, iphone]) {
      assert.match(body, /deadline=\$\(\(SECONDS \+ 1800\)\)/);
      assert.match(body, /while \(\( SECONDS < deadline \)\)/);
    }
    assert.doesNotMatch(watch, /if wait_for_watch_connected/);
  });
  console.log(`${passed} passed, 0 failed`);
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
