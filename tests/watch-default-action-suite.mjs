import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

function run(command, args, timeout = 120000) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout });
  assert.equal(result.status, 0, result.stdout + result.stderr + (result.error ?? ''));
  return result.stdout.trim();
}
const app = 'native/LazenskyCommanderApp/LazenskyCommanderWatchApp';
const source = fs.readFileSync(`${app}/LazenskyCommanderWatchApp.swift`, 'utf8');
assert.doesNotMatch(source, /WKNotificationScene\s*\(|WKUserNotificationHostingController|notificationRouteRevision/);
assert.match(source, /WindowGroup\s*\{\s*WatchCommanderView\(model: model\)/);
assert.match(source, /UNUserNotificationCenter.current\(\).delegate = notificationDelegate/);
const callback = source.slice(source.indexOf('didReceive response:'), source.indexOf('willPresent notification:'));
assert.match(callback, /guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else \{ return \}/);
assert.doesNotMatch(callback, /response.notification|userInfo|categoryIdentifier/);
assert.match(callback, /Task \{ @MainActor \[model\] in\s*await model.bootstrap\(\)/);
assert.doesNotMatch(callback.slice(0, callback.indexOf('Task {')), /\bawait\b(?! cache)/);
console.log('PASS system default action wiring has no custom scene, payload gate, or awaited service');
run('swift', ['build', '--package-path', 'native/LazenskyCommander']);
const bin = run('swift', ['build', '--package-path', 'native/LazenskyCommander', '--show-bin-path']);
const outputDir = path.resolve('.build/spa-production-closure');
fs.mkdirSync(outputDir, { recursive: true });
const output = path.join(outputDir, 'watch-model-regressions');
const nativeLayout = fs.existsSync(`${bin}/Modules`);
const objects = nativeLayout ? fs.readdirSync(`${bin}/LazenskyCommanderCore.build`)
  .filter(name => name.endsWith('.o')).map(name => `${bin}/LazenskyCommanderCore.build/${name}`)
  : [`${bin}/libLazenskyCommanderCore.a`];
run('xcrun', ['swiftc', '-parse-as-library',
  '-I', nativeLayout ? `${bin}/Modules` : bin, ...objects,
  `${app}/WatchCommanderModel.swift`, `${app}/WatchStandaloneAlarmPreferences.swift`,
  'tests/fixtures/watch-default-action-harness.swift', '-o', output]);
console.log(run(output, [], 20000));
