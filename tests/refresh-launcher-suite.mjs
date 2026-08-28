import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const launcherPath = path.join(root, 'Obnovit Lázeňský Commander.command');
const launcher = await fs.readFile(launcherPath, 'utf8');
const cases = [];

async function test(name, run) {
  try {
    await run();
    cases.push({ name, ok: true });
  } catch (error) {
    cases.push({ name, ok: false, error: error.message });
  }
}

function extractBetween(start, end) {
  const startIndex = launcher.indexOf(start);
  const endIndex = launcher.indexOf(end, startIndex);
  assert.notEqual(startIndex, -1, `Missing launcher marker: ${start}`);
  assert.notEqual(endIndex, -1, `Missing launcher marker: ${end}`);
  return launcher.slice(startIndex, endIndex);
}

await test('launcher shell syntax is valid', async () => {
  const result = spawnSync('bash', ['-n', launcherPath], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

await test('iPhone still requires CoreDevice Developer Mode', async () => {
  const iphonePolicy = extractBetween(
    'if [[ "$platform" == "iOS" && "$device_type" == "iPhone" ]]; then',
    'elif [[ "$platform" == "watchOS" && "$device_type" == "appleWatch" ]]; then'
  );
  assert.match(iphonePolicy, /if \[\[ "\$developer_mode" != "enabled" \]\]; then\s+DEV_MODE_DISABLED_SEEN=1\s+continue/);
});

await test('paired Watch with identifiers reaches Xcode despite a disabled CoreDevice flag', async () => {
  const watchPolicy = extractBetween(
    'elif [[ "$platform" == "watchOS" && "$device_type" == "appleWatch" ]]; then',
    '\n  fi\ndone'
  );
  assert.match(watchPolicy, /if \[\[ "\$pairing_state" != "paired" \]\]; then[\s\S]*?continue/);
  assert.match(watchPolicy, /if \[\[ -z "\$identifier" \|\| -z "\$udid" \]\]; then[\s\S]*?continue/);
  assert.match(watchPolicy, /WATCH_READY_COUNT=\$\(\(WATCH_READY_COUNT \+ 1\)\)/);
  assert.match(watchPolicy, /WATCH_DEVELOPER_MODE="\$developer_mode"/);
  assert.doesNotMatch(watchPolicy, /if \[\[ "\$developer_mode" != "enabled" \]\]; then[\s\S]*?continue/);
});

await test('Xcode destination and build settings are the Watch authority', async () => {
  const destinationsIndex = launcher.indexOf('WATCH_DESTINATIONS_FILE="$TEMP_DIR/watch-destinations.txt"');
  const buildSettingsIndex = launcher.indexOf('WATCH_BUILD_SETTINGS_JSON="$TEMP_DIR/watch-build-settings.json"');
  const warningIndex = launcher.indexOf('WARNING: CoreDevice reported Apple Watch developerModeStatus=');
  assert.ok(destinationsIndex >= 0);
  assert.ok(buildSettingsIndex > destinationsIndex);
  assert.ok(warningIndex > buildSettingsIndex);
  assert.match(launcher, /-scheme "\$WATCH_SCHEME"[\s\S]*?-destination "platform=watchOS,id=\$WATCH_UDID"[\s\S]*?-showBuildSettings -json/);
  assert.match(launcher, /but Xcode accepted destination \$WATCH_UDID; continuing/);
});

await test('Watch build and install report real Developer Mode failures precisely', async () => {
  assert.match(launcher, /Xcode nemohl sestavit aplikaci pro Apple Watch, protože hodinky odmítly vývojářské připojení/);
  assert.match(launcher, /Apple Watch odmítly instalaci kvůli Režimu vývojáře/);
  assert.match(launcher, /device install app[\s\S]*?--device "\$WATCH_IDENTIFIER"[\s\S]*?"\$WATCH_PRODUCT_PATH"/);
});

const failed = cases.filter(item => !item.ok);
for (const item of cases) {
  console.log(`${item.ok ? 'PASS' : 'FAIL'} ${item.name}${item.error ? `: ${item.error}` : ''}`);
}
console.log(`Refresh launcher: ${cases.length - failed.length}/${cases.length} passed`);
if (failed.length) process.exitCode = 1;
