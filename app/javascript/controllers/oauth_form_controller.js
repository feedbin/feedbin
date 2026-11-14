import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="oauth-form"
export default class extends Controller {
  static targets = ["password", "submit"]

  // Return in the email field moves on instead of submitting half a form.
  next(event) {
    event.preventDefault()
    this.passwordTarget.focus()
  }

  // The browser scrolls the focused field above the keyboard, not the button
  // under it. Runs after the layout has made room for the keyboard.
  reveal(event) {
    if (!event.detail.offset) return

    requestAnimationFrame(() => {
      const viewport = window.visualViewport
      const visibleBottom = viewport.offsetTop + viewport.height
      const overflow = this.submitTarget.getBoundingClientRect().bottom + 16 - visibleBottom
      if (overflow > 0) window.scrollBy({ top: overflow, behavior: "smooth" })
    })
  }
}
