// v21: no-cache service worker. It clears old caches and then unregisters without navigation loops.
self.addEventListener('install', event => { self.skipWaiting(); });
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => caches.delete(k)));
    if (self.registration && self.registration.unregister) await self.registration.unregister();
  })());
});
self.addEventListener('fetch', event => { return; });
