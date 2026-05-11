const CACHE_NAME = "suunto-to-ssi-qr-v1";
const FILES = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.mjs",
  "./web-core.mjs",
  "./vendor/qrcode.js",
  "./manifest.webmanifest",
  "./assets/icon.svg",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(FILES)));
});

self.addEventListener("fetch", (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request)),
  );
});
