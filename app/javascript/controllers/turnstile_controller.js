import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { sitekey: String }
  static targets = ["widget", "form"]

  connect() {
    if (typeof turnstile !== "undefined") {
      this.render()
    } else {
      document.addEventListener("turnstileReady", () => this.render(), { once: true })
    }
  }

  render() {
    turnstile.render(this.widgetTarget, {
      sitekey: this.sitekeyValue,
      callback: (token) => this.verified(token),
    })
  }

  verified(token) {
    window.$(this.formTarget).submit()
  }
}
