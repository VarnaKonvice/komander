import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const launcherPath = 'Otestovat Lázeňský Commander.command';
const source = fs.readFileSync(launcherPath, 'utf8');
const appSource = fs.readFileSync('native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift', 'utf8');
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
  test('acceptance and production read-back await real launch maintenance', () => {
    const bootstrap = appSource.slice(appSource.indexOf('func bootstrap() async {'), appSource.indexOf('private func performLaunchMaintenance() async'));
    assert.match(bootstrap, /CommanderAcceptanceLaunchMode\.current != \.none \|\| CommanderAcceptanceLaunchMode\.productionReadback/);
    assert.match(bootstrap, /await performLaunchMaintenance\(\)\s*\n\s*return/);
    assert.match(bootstrap, /Task\.sleep\(nanoseconds: 2_000_000_000\)/);
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
  test('signal cleanup removes only this run temporary build directory', () => {
    const record = path.join(directory, 'derived-path');
    const lock = path.join(directory, 'signal-build');
    const result = run(`acquire_lock\nprepare_test_artifacts\nprintf '%s' "$DERIVED" > '${record}'\nkill -TERM $$`, lock);
    assert.equal(result.status, 143, result.stderr);
    const derived = fs.readFileSync(record, 'utf8');
    assert.match(derived, /^\/private\/tmp\/lc-commander-acceptance\./);
    assert.equal(fs.existsSync(derived), false);
    assert.equal(fs.existsSync(lock), false);
  });
  test('temporary build cleanup is idempotent and rebuild uses a fresh directory', () => {
    const result = run('acquire_lock\nprepare_test_artifacts\nfirst="$DERIVED"\ncleanup_test_artifacts\ncleanup_test_artifacts\nprepare_test_artifacts\n[[ "$first" != "$DERIVED" ]] || exit 8');
    assert.equal(result.status, 0, result.stderr);
  });
  test('cleanup preserves a path whose ownership changed', () => {
    const record = path.join(directory, 'foreign-derived-path');
    const result = run(`acquire_lock\nprepare_test_artifacts\nprintf '%s' "$DERIVED" > '${record}'\nprintf 'foreign' > "$DERIVED/.commander-owner"\ncleanup_test_artifacts`);
    assert.equal(result.status, 1, result.stderr);
    const derived = fs.readFileSync(record, 'utf8');
    assert.equal(fs.readFileSync(path.join(derived, '.commander-owner'), 'utf8'), 'foreign');
    fs.rmSync(derived, { recursive: true }); // This test created this fixture.
  });
  test('locked and disconnected wait loops stop at their deadline', () => {
    for (const device of ['watch', 'iphone']) {
      const start = source.indexOf(`wait_for_${device}_unlock() {`);
      const end = source.indexOf(device === 'watch' ? 'watch_handshake() {' : 'iphone_pid() {', start);
      const body = source.slice(start, end);
      // Replace only the blocking sleep; advance Bash's monotonic elapsed clock.
      const isolated = body.replaceAll('/bin/sleep 1', 'SECONDS=$((SECONDS + 1801))');
      const result = spawnSync('/bin/bash', ['-c', `status() { :; }\n${device}_is_unlocked() { return 1; }\n${isolated}\nwait_for_${device}_unlock`], { encoding: 'utf8', timeout: 5000 });
      assert.equal(result.status, 1, result.stderr);
    }
  });
  test('clock rollback cannot make event-boundary wait infinite', () => {
    const start = source.indexOf('wait_until_epoch() {');
    const end = source.indexOf('build_normal_pair() {', start);
    const body = source.slice(start, end).replaceAll('/bin/sleep 0.5', 'SECONDS=$((SECONDS + 121))');
    const result = spawnSync('/bin/bash', ['-c', `${body}\nwait_until_epoch 9999999999`], { encoding: 'utf8', timeout: 5000 });
    assert.equal(result.status, 1, result.stderr);
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
  const validate = (changes = {}, phase = 'watch-acknowledged', token = '12/3', count = '1') => {
    const file = path.join(directory, 'status.json');
    fs.writeFileSync(file, JSON.stringify({ requestID: 'new-request', phase,
      dataset: 'acceptance', expectedToken: '12/3', observedToken: '12/3',
      timestamp: new Date().toISOString(), alarmCount: 1, alarmsVerified: true, ...changes }));
    return spawnSync('/usr/bin/python3', ['native/acceptance-status.py', file,
      'new-request', phase, 'acceptance', token, count, '0']).status;
  };
  test('status validator accepts exact new run evidence', () => assert.equal(validate(), 0));
  test('status validator refuses stale run, projection, count and dataset', () => {
    for (const patch of [{requestID: 'old-request'}, {observedToken: '12/2'},
      {expectedToken: '11/3', observedToken: '11/3'}, {alarmCount: 0},
      {alarmsVerified: false}, {dataset: 'production'}, {timestamp: 'bad'}]) {
      assert.equal(validate(patch), 1, JSON.stringify(patch));
    }
  });
  test('activity readback cannot green old identity or an inactive phase', () => {
    assert.equal(validate({}, 'activity-active'), 0);
    assert.equal(validate({phase: 'activity-not-active'}, 'activity-active'), 1);
    assert.equal(validate({expectedToken: '11/3', observedToken: '11/3'}, 'activity-active'), 1);
  });
  test('cleanup evidence needs zero verified alarms but never an empty Watch ACK', () => {
    assert.equal(validate({alarmCount: 0, expectedToken: null, observedToken: null}, 'cleaned', '', '0'), 0);
    assert.equal(validate({alarmCount: 1}, 'cleaned', '', '0'), 1);
  });
  console.log(`${passed} passed, 0 failed`);
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
