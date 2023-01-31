import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="web-push"
export default class extends Controller {
  static values = {
    vapid: Array,
    permission: String,
    url: String
  }

  connect() {
    this.checkPermissions()
  }

  checkPermissions() {
    let checkWebPush = true
    if ("safari" in window && "pushNotification" in window.safari) {
      const data = $("#push-data").data()
      let permissionData = window.safari.pushNotification.permission(data.websiteId)

      if (permissionData.permission == "granted") {
        this.permissionValue = permissionData.permission
        checkWebPush = false
      }
    }

    if (checkWebPush && "Notification" in window) {
      this.permissionValue = Notification.permission
    }
  }

  activate(event) {
    const key = new Uint8Array(this.vapidValue);
    let result = navigator.serviceWorker.ready.then((serviceWorkerRegistration) => {
      serviceWorkerRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: key
      }).then((pushSubscription) => {
        $.post(this.urlValue, {device: {data: pushSubscription.toJSON()}})
        this.checkPermissions()
      }, (error) => {
        this.checkPermissions()
      });
    });
    event.preventDefault()
  }
}
