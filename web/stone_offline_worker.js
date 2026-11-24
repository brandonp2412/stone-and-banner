'use strict';

const scope = new URL(self.registration.scope);
const version = new URL(self.location.href).searchParams.get('v') || 'dev';
const prefix = 'stone-banner-offline:' + scope.pathname + ':';
const cacheName = prefix + version;
const asset = (path) => new URL(path, scope).href;

// Cache the app shell before taking control. Fonts and renderer assets are
// cached as the engine loads them; all bundled resource icon packs are small.
const packs = ['banner', 'treasury', 'carved-stone', 'game-icons',
  'mdi', 'fluent-emoji-flat', 'noto', 'twemoji'];
const goods = ['wood', 'brick', 'wheat', 'wool', 'ore', 'paper', 'cloth', 'coin'];
const shell = [
  'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'p2p.js',
  'manifest.json', 'favicon.png', 'version.json',
  'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json',
  'assets/FontManifest.json', 'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/fonts/NotoSans-Regular.ttf', 'assets/assets/fonts/NotoSans-Bold.ttf',
  'assets/assets/art/stone_banner_crest.jpg',
  ...packs.flatMap((pack) => goods.map((good) => 'assets/assets/icons/' + pack + '/' + good + '.png')),
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(cacheName);
    await cache.addAll(shell.map((path) => new Request(asset(path), {cache: 'reload'})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(prefix) && name !== cacheName) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== scope.origin ||
      !url.pathname.startsWith(scope.pathname)) return;
  const path = url.pathname.slice(scope.pathname.length);

  // The shell and bootstrap check for a new deployment online. They fall
  // back to the last complete installed build rather than mixing versions.
  if (request.mode === 'navigate' || path === 'flutter_bootstrap.js') {
    event.respondWith((async () => {
      const fallback = request.mode === 'navigate' ? asset('index.html') : asset(path);
      try {
        const response = await fetch(request);
        if (response.ok) return response;
      } catch (_) {}
      return (await (await caches.open(cacheName)).match(fallback)) || Response.error();
    })());
    return;
  }

  // Only cache this build's static files; never intercept signalling or APIs.
  if (!(shell.includes(path) || path.startsWith('assets/') ||
        path.startsWith('canvaskit/') || path.startsWith('icons/'))) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    const key = asset(path);
    const cached = await cache.match(key);
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok) await cache.put(key, response.clone());
    return response;
  })());
});
