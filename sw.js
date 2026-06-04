// Alan's Workout — Service Worker
// Handles background rest timer notifications

const SW_VERSION = 'v1';

// ── Install & Activate ──
self.addEventListener('install', e => {
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(self.clients.claim());
});

// ── Message handler ──
// The app sends messages to schedule/cancel notifications
let restTimer = null;

self.addEventListener('message', e => {
  const { type, remaining, endTime } = e.data || {};

  if (type === 'REST_START') {
    // Cancel any existing timer
    if (restTimer) clearTimeout(restTimer);

    // Calculate exact ms until rest ends
    const msLeft = endTime - Date.now();
    if (msLeft <= 0) return;

    restTimer = setTimeout(async () => {
      restTimer = null;

      // Check if app is visible — if so, don't send notification
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const appVisible = clients.some(c => c.visibilityState === 'visible');
      if (appVisible) return;

      // App is in background — fire notification
      self.registration.showNotification("Alan's Workout", {
        body: "Rest time's up — next set awaits 💪",
        icon: './icons/icon-192.png',
        badge: './icons/icon-192.png',
        tag: 'rest-done',
        requireInteraction: false,
        silent: false,
        vibrate: [200, 100, 200],
      });
    }, msLeft);
  }

  if (type === 'REST_CANCEL') {
    if (restTimer) {
      clearTimeout(restTimer);
      restTimer = null;
    }
  }
});

// ── Notification click — bring app to foreground ──
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      // Focus existing tab if open
      for (const client of clients) {
        if ('focus' in client) return client.focus();
      }
      // Otherwise open the app
      if (self.clients.openWindow) return self.clients.openWindow('./');
    })
  );
});
