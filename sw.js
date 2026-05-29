const CACHE_NAME = "conference-manager-v14-hard-mobile-fix";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith("/socket.io") || url.pathname.startsWith("/api")) return;
  event.respondWith(fetch(event.request, { cache: "no-store" }).catch(() => caches.match(event.request)));
});
