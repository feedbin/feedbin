import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="extension-link"
export default class extends Controller {
  static values = {
    browser: String,
  }

  connect() {
    this.browserValue = this.detectBrowser()
  }

  detectBrowser() {
    const userAgent = navigator.userAgent.toLowerCase()
    if (userAgent.includes("firefox")) {
      return "firefox"
    } else if (userAgent.includes("safari") && !userAgent.includes("chrome")) {
      return "safari"
    }
    return "chrome"
  }

}
