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
  const nextDateIndex = launcher.lastIndexOf('\nset_refresh_deadline_after_install\n');
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
  const iphoneRequired = extractBetween('DERIVED_DATA="$TEMP_DIR/DerivedData"', '\nset_refresh_deadline_after_install\n');
  assert.match(iphoneRequired, /fail "Sestavená aplikace nemá platný vývojářský podpis/);
  assert.match(iphoneRequired, /fail "Instalace na iPhone selhala/);
  assert.match(iphoneRequired, /fail "Instalace na iPhone proběhla, ale její výsledek se nepodařilo ověřit/);
  assert.match(iphoneRequired, /fail "Po instalaci nebyl Lázeňský Commander na iPhonu nalezen/);
});

await test('profile deadline wins and plus-six fallback is used only when profile dates are unavailable', async () => {
  const selection = extractBetween('set_refresh_deadline_after_install() {', '\n}\n\nWATCH_STATUS') + '\n}';
  for (const available of ['1', '0']) {
    const result = spawnSync('bash', ['-c', `
      log() { :; }
      status() { :; }
      exec 3>&1
      fallback_date() { printf 'FALLBACK_CALLED\\n' >&3; printf '04.01.2027'; }
      ${selection.replaceAll('/bin/date', 'fallback_date')}
      set_refresh_deadline_after_install
      printf '%s' "$NEXT_REFRESH_DATE"
    `], { encoding: 'utf8', env: { ...process.env, PROFILE_DATES_AVAILABLE: available,
      PROFILE_EXPIRATION_DATE: '02.01.2027 12:00', NEXT_REFRESH_DATE: '01.01.2027', LOG_FILE: '/dev/null' } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, available === '1' ? '01.01.2027' : 'FALLBACK_CALLED\n04.01.2027');
    assert.equal(result.stdout.includes('FALLBACK_CALLED'), available === '0');
  }
  assert.match(selection, /TZ=Europe\/Prague \/bin\/date -v\+6d/);
  assert.match(launcher, /DALŠÍ OBNOVA NEJPOZDĚJI: \$NEXT_REFRESH_DATE/);
});

await test('double click defaults to main and explicit test override survives launcher re-execution', async () => {
  const assignment = launcher.match(/^TARGET_BRANCH=.*$/m)?.[0];
  assert.ok(assignment);
  for (const [override, expected] of [['', 'main'], ['lc/unified-native-app-v1', 'lc/unified-native-app-v1']]) {
    const result = spawnSync('bash', ['-c', `${assignment}\nprintf '%s' "$TARGET_BRANCH"`], {
      encoding: 'utf8', env: { ...process.env, LC_REFRESH_TARGET_BRANCH: override }
    });
    assert.equal(result.stdout, expected);
  }
  assert.match(launcher, /git check-ref-format "refs\/heads\/\$TARGET_BRANCH"/);
  assert.match(launcher, /\/usr\/bin\/env LC_REFRESH_TARGET_BRANCH="\$TARGET_BRANCH"/);
});

await test('embedded profile is read after signature verification and expired profiles cannot be installed', async () => {
  const signed = launcher.indexOf('codesign --verify --strict "$APP_PATH"');
  const read = launcher.indexOf('if read_profile_refresh_dates "$APP_PATH/embedded.mobileprovision"');
  const install = launcher.indexOf('INSTALL_JSON="$TEMP_DIR/iphone-install.json"');
  assert.ok(signed < read && read < install);
  assert.match(launcher, /security cms -D -i "\$profile" -o "\$decoded"/);
  assert.match(launcher, /plist_raw CreationDate/);
  assert.match(launcher, /plist_raw ExpirationDate/);
  assert.match(launcher, /TZ=Europe\/Prague \/bin\/date -r "\$expiration_epoch" -v-1d/);
  assert.match(launcher, /fail "Xcode vytvořil aplikaci s již prošlým provisioning profilem/);
});

if (process.platform === 'darwin') {
  await test('BSD date uses actual profile expiration across DST and rejects invalid metadata', async () => {
    const reader = extractBetween('read_profile_refresh_dates() {', '\n}\n\nset_refresh_deadline_after_install') + '\n}';
    for (const [creation, expiration, expected] of [
      ['2026-08-31T10:00:00Z', '2026-09-07T10:00:00Z', '06.09.2026'],
      ['2026-09-02T10:00:00Z', '2026-09-09T10:00:00Z', '08.09.2026'],
      ['2026-03-22T10:00:00Z', '2026-03-29T10:00:00Z', '28.03.2026'],
      ['2026-10-18T11:00:00Z', '2026-10-25T11:00:00Z', '24.10.2026'],
      ['2026-12-25T11:00:00Z', '2027-01-01T11:00:00Z', '31.12.2026'],
      ['', '', 'UNAVAILABLE'],
      ['2026-09-08T10:00:00Z', '2026-09-07T10:00:00Z', 'UNAVAILABLE'],
      ['2026-08-31T10:00:00Z', '2026-09-31T10:00:00Z', 'UNAVAILABLE']
    ]) {
      const result = spawnSync('bash', ['-c', `
        log() { :; }
        decode_fixture() { return 0; }
        plist_raw() { if [[ "$1" == CreationDate ]]; then printf '%s' "$CREATION"; else printf '%s' "$EXPIRATION"; fi; }
        ${reader.replace('/usr/bin/security', 'decode_fixture')}
        if read_profile_refresh_dates fixture unused; then printf '%s' "$NEXT_REFRESH_DATE"; else printf UNAVAILABLE; fi
      `], { encoding: 'utf8', env: { ...process.env, CREATION: creation, EXPIRATION: expiration, LOG_FILE: '/dev/null' } });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, expected);
    }
    const fallback = spawnSync('bash', ['-c', "TZ=Europe/Prague /bin/date -j -v+6d -f '%Y-%m-%d %H:%M' '2026-12-29 12:00' '+%d.%m.%Y'"], { encoding: 'utf8' });
    assert.equal(fallback.status, 0, fallback.stderr);
    assert.equal(fallback.stdout.trim(), '04.01.2027');
  });
}

await test('verified iPhone is opened to refresh its reminder before optional Watch deployment', async () => {
  const verified = launcher.indexOf('iPhone post-install verification: success');
  const launch = launcher.indexOf('"$DEVICECTL" device process launch');
  const watch = launcher.lastIndexOf('\nattempt_watch_refresh\n');
  assert.ok(verified < launch && launch < watch);
  const command = extractBetween('IPHONE_LAUNCH_JSON=', '\nattempt_watch_refresh()');
  assert.match(command, /--device "\$DEVICE_IDENTIFIER"/);
  assert.match(command, /"\$APP_BUNDLE_ID"/);
  assert.match(command, /plist_raw info.outcome "\$IPHONE_LAUNCH_JSON"/);
  assert.doesNotMatch(command, /uninstall|terminate-existing/);
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
