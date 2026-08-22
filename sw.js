const CACHE_NAME = 'komander-pwa-v6';
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './landscape-fix.css?v=45',
  './day-overview-v1.css?v=20',
  './day-overview-v1.js?v=18',
  './public-schedule-feed.js?v=3',
  './pwa-install.js',
  './assets/icons/lazensky-v1/icon-map.json',
  './assets/icons/lazensky-v1/colors.json',
  './assets/icons/lazensky-v1/icons/256/electro_therapy.png',
  './assets/icons/lazensky-v1/icons/256/hydrojet.png',
  './assets/icons/lazensky-v1/icons/256/imoove.png',
  './assets/icons/lazensky-v1/icons/256/individual_rehab.png',
  './assets/icons/lazensky-v1/icons/256/iodobrom.png',
  './assets/icons/lazensky-v1/icons/256/massage.png',
  './assets/icons/lazensky-v1/icons/256/meal_breakfast.png',
  './assets/icons/lazensky-v1/icons/256/meal_dinner.png',
  './assets/icons/lazensky-v1/icons/256/meal_lunch.png',
  './assets/icons/lazensky-v1/icons/256/peat_wrap.png',
  './assets/icons/lazensky-v1/icons/256/pool.png',
  './assets/icons/lazensky-v1/icons/256/whirlpool.png',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png'
];
const APP_SHELL_URLS = new Set(APP_SHELL.map(path => new URL(path, self.registration.scope).href));

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => key.startsWith('komander-') && key !== CACHE_NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const request = event.request;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // The public feed is always read from the network; localStorage keeps the last valid version offline.
  if (url.pathname.endsWith('/data/schedule.json')) return;

  event.respondWith((async () => {
    try {
      const response = await fetch(request, { cache: 'no-store' });
      if (response.ok && (request.mode === 'navigate' || APP_SHELL_URLS.has(url.href))) {
        const cache = await caches.open(CACHE_NAME);
        cache.put(request, response.clone());
      }
      return response;
    } catch (error) {
      const cached = await caches.match(request);
      if (cached) return cached;
      if (request.mode === 'navigate') return caches.match('./index.html');
      throw error;
    }
  })());
});
