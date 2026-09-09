/* Service worker del Registro presenze: serve SOLO per le notifiche push.
   Non mette in cache nessun file: la pagina si aggiorna come sempre. */

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let dati = {};
  try { dati = e.data ? e.data.json() : {}; } catch (_) { dati = { body: e.data ? e.data.text() : '' }; }
  const titolo = dati.title || 'Registro presenze';
  const opzioni = {
    body: dati.body || '',
    icon: 'icone/icona-192.png',
    badge: 'icone/icona-192.png',
    tag: dati.tag || 'registro',
    renotify: true,
    data: { url: dati.url || './' },
  };
  e.waitUntil(self.registration.showNotification(titolo, opzioni));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil((async () => {
    const finestre = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of finestre) { if ('focus' in w) { await w.focus(); return; } }
    if (self.clients.openWindow) await self.clients.openWindow(url);
  })());
});
