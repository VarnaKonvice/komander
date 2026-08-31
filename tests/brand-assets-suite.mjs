import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const brandRoot = path.join(root, 'assets/brand/lazensky-commander-v1');
const nativeRoot = path.join(root, 'native/LazenskyCommanderApp');

async function pngInfo(file) {
  const bytes = await fs.readFile(file);
  assert.equal(bytes.subarray(1, 4).toString('ascii'), 'PNG', `${file} is not a PNG`);
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    hasAlpha: [4, 6].includes(bytes[25])
  };
}

async function assertPng(relativePath, size, hasAlpha) {
  const info = await pngInfo(path.join(root, relativePath));
  assert.deepEqual(info, { width: size, height: size, hasAlpha }, relativePath);
}

const cases = [];
async function test(name, run) {
  try {
    await run();
    cases.push({ name, ok: true });
  } catch (error) {
    cases.push({ name, ok: false, error: error.message });
  }
}

await test('brand masters preserve the three approved roles', async () => {
  await assertPng('assets/brand/lazensky-commander-v1/masters/launcher-full-1024.png', 1024, false);
  await assertPng('assets/brand/lazensky-commander-v1/masters/circular-mark-1024.png', 1024, true);
  await assertPng('assets/brand/lazensky-commander-v1/masters/small-glyph-1024.png', 1024, true);
  const reference = await pngInfo(path.join(brandRoot, 'reference/approved-reference.png'));
  assert.deepEqual({ width: reference.width, height: reference.height }, { width: 1254, height: 1254 });
});

await test('PWA exports have complete dimensions and alpha roles', async () => {
  await assertPng('assets/brand/lazensky-commander-v1/pwa/launcher-192.png', 192, false);
  await assertPng('assets/brand/lazensky-commander-v1/pwa/launcher-512.png', 512, false);
  await assertPng('assets/brand/lazensky-commander-v1/pwa/apple-touch-icon-180.png', 180, false);
  await assertPng('assets/brand/lazensky-commander-v1/pwa/favicon-32.png', 32, true);
  await assertPng('assets/brand/lazensky-commander-v1/pwa/header-mark-180.png', 180, true);
});

await test('PWA manifest uses the new launcher assets and brand colors', async () => {
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'manifest.webmanifest'), 'utf8'));
  assert.equal(manifest.background_color, '#2B1A4D');
  assert.equal(manifest.theme_color, '#6E56CF');
  assert.deepEqual(manifest.icons.map(icon => icon.src), [
    'assets/brand/lazensky-commander-v1/pwa/launcher-192.png',
    'assets/brand/lazensky-commander-v1/pwa/launcher-512.png'
  ]);
  assert.equal(manifest.icons[1].purpose, 'any maskable');
});

await test('PWA document and offline cache use every runtime brand asset', async () => {
  const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
  const worker = await fs.readFile(path.join(root, 'sw.js'), 'utf8');
  const runtimeAssets = [
    'launcher-192.png',
    'launcher-512.png',
    'apple-touch-icon-180.png',
    'favicon-32.png',
    'header-mark-180.png'
  ];
  assert.match(index, /rel="icon"[^>]+favicon-32\.png/);
  assert.match(index, /rel="apple-touch-icon"[^>]+apple-touch-icon-180\.png/);
  assert.match(index, /class="logo"[^>]+header-mark-180\.png/);
  assert.match(worker, /komander-pwa-v8/);
  runtimeAssets.forEach(asset => assert.match(worker, new RegExp(asset.replace('.', '\\.'))));
  assert.doesNotMatch(index, /(?:src|href)="\.\/icon-(180|192|512)\.png"/);
  assert.doesNotMatch(worker, /'\.\/icon-(180|192|512)\.png'/);
  for (const oldAsset of ['icon-180.png', 'icon-192.png', 'icon-512.png', 'icon-1024.png']) {
    await assert.rejects(fs.access(path.join(root, oldAsset)), `${oldAsset} still exists beside Brand Foundation v1`);
  }
});

await test('iPhone AppIcon is a complete opaque 1024-point source', async () => {
  const catalog = path.join(nativeRoot, 'LazenskyCommanderApp/AppAssets.xcassets/AppIcon.appiconset');
  const contents = JSON.parse(await fs.readFile(path.join(catalog, 'Contents.json'), 'utf8'));
  assert.deepEqual(contents.images[0], {
    filename: 'AppIcon-1024.png',
    idiom: 'universal',
    platform: 'ios',
    size: '1024x1024'
  });
  await assertPng('native/LazenskyCommanderApp/LazenskyCommanderApp/AppAssets.xcassets/AppIcon.appiconset/AppIcon-1024.png', 1024, false);
});

await test('Watch AppIcon is a complete opaque circular-brand source', async () => {
  const catalog = path.join(nativeRoot, 'LazenskyCommanderWatchApp/WatchAssets.xcassets/WatchAppIcon.appiconset');
  const contents = JSON.parse(await fs.readFile(path.join(catalog, 'Contents.json'), 'utf8'));
  assert.deepEqual(contents.images[0], {
    filename: 'WatchAppIcon-1024.png',
    idiom: 'universal',
    platform: 'watchos',
    size: '1024x1024'
  });
  await assertPng('native/LazenskyCommanderApp/LazenskyCommanderWatchApp/WatchAssets.xcassets/WatchAppIcon.appiconset/WatchAppIcon-1024.png', 1024, false);
});

await test('shared native marks provide complete transparent 1x 2x 3x assets', async () => {
  for (const [name, prefix] of [['BrandCircularMark', 'BrandCircularMark'], ['BrandSmallGlyph', 'BrandSmallGlyph']]) {
    const imageset = path.join(nativeRoot, `Shared/BrandAssets.xcassets/${name}.imageset`);
    const contents = JSON.parse(await fs.readFile(path.join(imageset, 'Contents.json'), 'utf8'));
    assert.deepEqual(contents.images.map(image => image.scale), ['1x', '2x', '3x']);
    for (const size of [128, 256, 384]) {
      await assertPng(`native/LazenskyCommanderApp/Shared/BrandAssets.xcassets/${name}.imageset/${prefix}-${size}.png`, size, true);
    }
  }
});

await test('Xcode target membership and shared Swift names are explicit', async () => {
  const project = await fs.readFile(path.join(nativeRoot, 'LazenskyCommanderApp.xcodeproj/project.pbxproj'), 'utf8');
  const helper = await fs.readFile(path.join(nativeRoot, 'Shared/CommanderBrandAssets.swift'), 'utf8');
  assert.match(project, /AppAssets\.xcassets in Resources/);
  assert.match(project, /WatchAssets\.xcassets in Resources/);
  assert.equal((project.match(/BrandAssets\.xcassets in Resources \*\//g) || []).length, 8);
  assert.equal((project.match(/CommanderBrandAssets\.swift in Sources \*\//g) || []).length, 8);
  assert.equal((project.match(/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;/g) || []).length, 2);
  assert.equal((project.match(/ASSETCATALOG_COMPILER_APPICON_NAME = WatchAppIcon;/g) || []).length, 2);
  assert.match(helper, /circularMarkName = "BrandCircularMark"/);
  assert.match(helper, /smallGlyphName = "BrandSmallGlyph"/);
});

await test('brand palette matches the approved reference', async () => {
  const colors = JSON.parse(await fs.readFile(path.join(root, 'assets/icons/lazensky-v1/colors.json'), 'utf8'));
  assert.deepEqual(colors.brand, {
    commanderPurple: '#6E56CF',
    commanderPurpleDark: '#4C359B',
    commanderPurpleLight: '#A178FF',
    waterBlue: '#38B6FF',
    timeGold: '#FFC45A',
    brandSurfaceDark: '#2B1A4D'
  });
});

await test('procedure icon contract remains unchanged and separate from branding', async () => {
  const iconMap = JSON.parse(await fs.readFile(path.join(root, 'assets/icons/lazensky-v1/icon-map.json'), 'utf8'));
  const colors = JSON.parse(await fs.readFile(path.join(root, 'assets/icons/lazensky-v1/colors.json'), 'utf8'));
  assert.deepEqual(iconMap.icons.map(icon => icon.key), [
    'meal_breakfast', 'meal_lunch', 'meal_dinner', 'pool', 'iodobrom', 'whirlpool',
    'peat_wrap', 'imoove', 'massage', 'hydrojet', 'electro_therapy', 'individual_rehab'
  ]);
  assert.deepEqual(colors.procedures, {
    meal: '#F59E0B',
    pool: '#0EA5B7',
    iodobrom: '#B27A2C',
    whirlpool: '#38BDF8',
    peat_wrap: '#5B3A29',
    imoove: '#149B91',
    massage: '#65A30D',
    hydrojet: '#0EA5E9',
    electro_therapy: '#6D5BD0',
    individual_rehab: '#22A06B'
  });
  assert.equal(iconMap.fallback.key, null);
});

const failed = cases.filter(item => !item.ok);
for (const item of cases) {
  console.log(`${item.ok ? 'PASS' : 'FAIL'} ${item.name}${item.error ? `: ${item.error}` : ''}`);
}
console.log(`Brand assets: ${cases.length - failed.length}/${cases.length} passed`);
if (failed.length) process.exitCode = 1;
