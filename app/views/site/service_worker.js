self.addEventListener("install", event => {

});
self.addEventListener("activate", event => {

});
self.addEventListener("fetch", event => {

});

self.addEventListener("push", (event) => {
  let data = event.data.json();
  let result = self.registration.showNotification(data.title, data.payload);
  event.waitUntil(result);
});

self.addEventListener ("notificationclick", async function (event) {
  if (event.action) {
    clients.openWindow(event.action);
  } else {
    clients.openWindow(event.notification.data.defaultAction);
  }
});
