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

await test('verified iPhone install precedes every optional Watch attempt', async () => {
  const iphoneVerifiedIndex = launcher.indexOf('iPhone post-install verification: success');
  const nextDateIndex = launcher.indexOf('NEXT_REFRESH_DATE="$(/bin/date -v+6d');
  const watchAttemptIndex = launcher.lastIndexOf('\nattempt_watch_refresh\n');
  assert.ok(iphoneVerifiedIndex >= 0);
  assert.ok(nextDateIndex > iphoneVerifiedIndex);
  assert.ok(watchAttemptIndex > nextDateIndex);
});

await test('all Watch deployment failures are non-blocking', async () => {
  const watchAttempt = extractBetween('attempt_watch_refresh() {', '\n}\n\nattempt_watch_refresh');
  assert.doesNotMatch(watchAttempt, /\bfail\s+"/);
  assert.match(watchAttempt, /skip_watch "Watch build nebo provisioning selhal"/);
  assert.match(watchAttempt, /skip_watch "instalace Watch aplikace selhala"/);
  assert.match(watchAttempt, /skip_watch "instalaci Watch aplikace se nepodařilo ověřit"/);
  assert.match(launcher, /device install app[\s\S]*?--device "\$WATCH_IDENTIFIER"[\s\S]*?"\$WATCH_PRODUCT_PATH"/);
  assert.match(launcher, /WATCH: přeskočeno – nativní Watch aplikace nebyla obnovena/);
});

await test('iPhone build install and verification failures remain blocking', async () => {
  const iphoneRequired = extractBetween('DERIVED_DATA="$TEMP_DIR/DerivedData"', 'NEXT_REFRESH_DATE="$(/bin/date -v+6d');
  assert.match(iphoneRequired, /fail "Sestavená aplikace nemá platný vývojářský podpis/);
  assert.match(iphoneRequired, /fail "Instalace na iPhone selhala/);
  assert.match(iphoneRequired, /fail "Instalace na iPhone proběhla, ale její výsledek se nepodařilo ověřit/);
  assert.match(iphoneRequired, /fail "Po instalaci nebyl Lázeňský Commander na iPhonu nalezen/);
});

await test('next refresh is six calendar days after successful iPhone verification', async () => {
  assert.match(launcher, /NEXT_REFRESH_DATE="\$\(\/bin\/date -v\+6d '\+%d\.%m\.%Y'/);
  const fixture = new Date(Date.UTC(2026, 11, 29));
  fixture.setUTCDate(fixture.getUTCDate() + 6);
  assert.equal(fixture.toISOString().slice(0, 10), '2027-01-04');
  assert.match(launcher, /DALŠÍ OBNOVA NEJPOZDĚJI: \$NEXT_REFRESH_DATE/);
});

await test('final summary makes iPhone success independent from Watch status', async () => {
  assert.match(launcher, /HOTOVO – \$APP_NAME na iPhonu byl obnoven/);
  assert.match(launcher, /Nainstalovaná větev \+ commit: \$TARGET_BRANCH @ \$GIT_COMMIT_SHORT/);
  assert.match(launcher, /status "iPhone: OK"/);
  assert.match(launcher, /WATCH: OK – nativní Watch aplikace byla obnovena/);
});

const failed = cases.filter(item => !item.ok);
for (const item of cases) {
  console.log(`${item.ok ? 'PASS' : 'FAIL'} ${item.name}${item.error ? `: ${item.error}` : ''}`);
}
console.log(`Refresh launcher: ${cases.length - failed.length}/${cases.length} passed`);
if (failed.length) process.exitCode = 1;
