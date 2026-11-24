{{flutter_js}}
{{flutter_build_config}}

// Flutter's deprecated worker now unregisters itself. Keep local games
// reloadable offline and serve CanvasKit from this site's own build.
(async () => {
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
  _flutter.loader.load({
    config: { canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href },
  });
})();
