/* Service Worker: macht TanaSR offline lauffaehig.
 * - App-Shell: network-first mit kurzem Timeout, Cache als Rueckfall. Damit ist
 *   eine neu deployte Version sofort da statt erst beim uebernaechsten Start,
 *   und ohne Netz startet die App trotzdem.
 * - Medien (Bilder, Xeno-Canto-Audio): cache-first, wird von app.js vorgeladen
 * - Dropbox-API (POST): nie abfangen
 */
const SHELL_CACHE = 'tanasr-shell-v1';
const MEDIA_CACHE = 'tanasr-media-v1';
const SHELL = [
  './',
  'index.html',
  'style.css',
  'app.js',
  'manifest.webmanifest',
  'icon-192.png',
  'icon-512.png',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then(cache => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== SHELL_CACHE && key !== MEDIA_CACHE && !key.startsWith('tanasr-data'))
            .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.hostname.endsWith('dropboxapi.com')) return;

  if (url.origin === self.location.origin) {
    event.respondWith(networkFirst(request));
  } else {
    event.respondWith(cacheFirst(request));
  }
});

const NETWORK_TIMEOUT_MS = 3000;

async function networkFirst(request) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const response = await Promise.race([
      fetch(request),
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), NETWORK_TIMEOUT_MS)),
    ]);
    if (response.ok) cache.put(request, response.clone());
    return response;
  } catch (err) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(MEDIA_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok || response.type === 'opaque') cache.put(request, response.clone());
  return response;
}
