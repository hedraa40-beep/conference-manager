// v20 no-cache service worker: unregister old worker and clear caches
self.addEventListener('install', event => { self.skipWaiting(); });
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => caches.delete(k)));
    if (self.registration && self.registration.unregister) await self.registration.unregister();
    const clientsList = await self.clients.matchAll({type:'window', includeUncontrolled:true});
    for (const client of clientsList) client.navigate(client.url);
  })());
});
self.addEventListener('fetch', event => { return; });
