{{flutter_js}}
{{flutter_build_config}}

// Flutter's deprecated worker now unregisters itself. Keep local games
// reloadable offline and serve CanvasKit from this site's own build.
async function prepareOffline() {
  if ('serviceWorker' in navigator && window.isSecureContext) {
    try {
      const workerUrl = new URL('stone_offline_worker.js', document.baseURI);
      workerUrl.searchParams.set('v', {{flutter_service_worker_version}});
      const registration = await navigator.serviceWorker.register(workerUrl, {
        updateViaCache: 'none',
      });
      const worker = registration.installing || registration.waiting || registration.active;
      if (worker && worker.state !== 'activated') {
        await new Promise((resolve) => {
          const done = () => {
            if (worker.state === 'activated' || worker.state === 'redundant') {
              worker.removeEventListener('statechange', done);
              resolve();
            }
          };
          worker.addEventListener('statechange', done);
          done();
        });
      }
      if (registration.active) await navigator.serviceWorker.ready;
    } catch (_) {
      // Private mode or an unavailable worker must not block local play.
    }
  }
}

(async () => {
  const controlled = !!navigator.serviceWorker?.controller;
  const offline = prepareOffline();
  // A returning controlled page must switch to the new version before loading
  // its Dart bundle. A first visit has no old worker and can start immediately.
  if (controlled) await offline;
  if (!controlled) {
    window.addEventListener('flutter-first-frame', async () => {
      await offline;
      const worker = navigator.serviceWorker?.controller;
      if (!worker) return;
      // Some engine/font requests may have completed before the worker took
      // control. Save them for the first subsequent offline reload.
      worker.postMessage({
        type: 'cache-startup-resources',
        urls: performance.getEntriesByType('resource').map(entry => entry.name),
      });
    }, { once: true });
  }
  try {
    await _flutter.loader.load({
      config: { canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href },
    });
  } catch (_) {
    const message = document.getElementById('stone-loading-message');
    if (message) message.textContent = 'Could not load the game. Please reload.';
  }
})();
