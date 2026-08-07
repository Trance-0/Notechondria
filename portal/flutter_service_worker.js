'use strict';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try { await self.registration.unregister(); } catch (e) {}
    try {
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        if (client.url && 'navigate' in client) {
          try { client.navigate(client.url); } catch (e) {}
        }
      }
    } catch (e) {}
  })());
});
