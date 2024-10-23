import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="web-push"
export default class extends Controller {
  static values = {
    vapid: Array,
    permission: String,
    url: String,
    tokens: Array,
  }

  connect() {
    this.checkPermissions()
  }

  checkPermissions() {
    let checkWebPush = true
    if ("safari" in window && "pushNotification" in window.safari) {
      const data = window.$("#push-data").data()
      let permissionData = window.safari.pushNotification.permission(
        data.websiteId
      )

      if (permissionData.permission == "granted") {
        this.permissionValue = permissionData.permission
        checkWebPush = false
      }
    }

    if (checkWebPush && "Notification" in window) {
      this.permissionValue = Notification.permission
      if (this.permissionValue === "granted") {
        this.register()
      }
    }
  }

  activate(event) {
    this.register()
    event.preventDefault()
  }

  register() {
    const key = new Uint8Array(this.vapidValue)
    navigator.serviceWorker.ready.then((serviceWorkerRegistration) => {
      serviceWorkerRegistration.pushManager
        .subscribe({
          userVisibleOnly: true,
          applicationServerKey: key,
        })
        .then((pushSubscription) => {
            if (!this.tokensValue.includes(pushSubscription.endpoint)) {
              window.$.post(this.urlValue, {
                device: { data: pushSubscription.toJSON() },
              })
            }
            this.permissionValue = Notification.permission
          },
          (error) => {
            console.log(error)
            this.permissionValue = Notification.permission
          }
        )
    })
  }
}
