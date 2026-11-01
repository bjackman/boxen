const sw = globalThis as unknown as ServiceWorkerGlobalScope;

sw.addEventListener("push", (event) => {
  const { title, body, tag } = event.data?.json() as { title: string; body: string; tag: string };
  event.waitUntil(
    (async () => {
      const windows = await sw.clients.matchAll({ type: "window" });
      // A push subscribed as userVisibleOnly must show something.
      const silent = windows.some((w) => w.focused);
      await sw.registration.showNotification(title, { body, tag, icon: "/icon.svg", silent });
    })(),
  );
});

sw.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const [client] = await sw.clients.matchAll({ type: "window" });
      if (client) await client.focus();
      else await sw.clients.openWindow("/");
    })(),
  );
});
