// v18: no offline cache. Clear any old cache and unregister this worker.
self.addEventListener('install', event => { self.skipWaiting(); });
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
      await self.registration.unregister();
      const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of clientsList) {
        const u = new URL(client.url);
        client.navigate(u.origin + u.pathname + '?v=18&swclear=' + Date.now() + u.hash);
      }
    } catch (e) {}
  })());
});
self.addEventListener('fetch', event => { return; });
