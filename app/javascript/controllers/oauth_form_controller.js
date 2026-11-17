import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="oauth-form"
export default class extends Controller {
  static targets = ["password", "submit"]

  // Return in the email field moves on instead of submitting half a form.
  next(event) {
    event.preventDefault()
    this.passwordTarget.focus()
  }

  disconnect() {
    this.stopWaiting()
  }

  // The browser scrolls the focused field above the keyboard, not the button
  // under it, so this brings the button up too.
  //
  // When the keyboard first comes up that happens at once, after the layout
  // has made room for it. When it is already up and focus moves to another
  // field, the browser scrolls that field into view itself, and a scroll
  // started here meanwhile is thrown away by it: the page starts up, snaps
  // back and starts again. So then this waits until the page has stopped
  // moving, and only adds what the browser's scroll left out.
  reveal(event) {
    const offset = event.detail.offset
    const wasUp = this.keyboardOffset > 0
    this.keyboardOffset = offset
    this.stopWaiting()
    if (!offset) return

    if (wasUp) {
      this.waitForStillness()
    } else {
      requestAnimationFrame(() => this.revealSubmit())
    }
  }

  // Every scroll of the page or of the visible part of it puts the wait off.
  waitForStillness() {
    if (!this.postpone) {
      this.postpone = () => this.waitForStillness()
      window.addEventListener("scroll", this.postpone, { passive: true })
      window.visualViewport.addEventListener("scroll", this.postpone)
    }
    clearTimeout(this.stillness)
    this.stillness = setTimeout(() => {
      this.stopWaiting()
      this.revealSubmit()
    }, 100)
  }

  stopWaiting() {
    clearTimeout(this.stillness)
    if (!this.postpone) return
    window.removeEventListener("scroll", this.postpone)
    window.visualViewport.removeEventListener("scroll", this.postpone)
    this.postpone = null
  }

  // The button's place is measured from the top of the page as the browser
  // has scrolled it, so the bottom of what shows is too: `offsetTop` isn't
  // that once the page has scrolled (iOS reports the page's own scroll in
  // it), which put the button a scroll's length inside what shows however
  // far under the keyboard it was.
  revealSubmit() {
    const viewport = window.visualViewport
    const visibleBottom = viewport.pageTop - window.scrollY + viewport.height
    const overflow = this.submitTarget.getBoundingClientRect().bottom + 16 - visibleBottom
    if (overflow > 0) window.scrollBy({ top: overflow, behavior: "smooth" })
  }
}
