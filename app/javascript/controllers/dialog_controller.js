import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

export default class extends Controller {
  static targets = ["content", "footerSpacer", "headerBorder", "footerBorder"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    headerBorder: Boolean,
    footerBorder: Boolean,
    purpose: String,
  }

  connect() {
    // remap cancel to custom cancel
    this.boundCancel = this.cancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)

    this.checkScroll()
    this.boundCheckScroll = this.checkScroll.bind(this)
    window.addEventListener("resize", this.boundCheckScroll)
  }

  disconnect() {
    this.element.removeEventListener("cancel", this.boundCancel)
    window.removeEventListener("resize", this.boundCheckScroll)
  }

  openWithPurpose(event) {
    if (event?.detail?.purpose == this.purposeValue) {
      this.open()
    }
  }

  open() {
    const showEvent = this.dispatch("willShow")
    if (!showEvent.defaultPrevented) {
      this.element.showModal()
      this.checkScroll()
      setTimeout(() => {
        this.dispatch("shown")
      }, 350)
    }
  }

  close() {
    const hideEvent = this.dispatch("willHide")

    if (!hideEvent.defaultPrevented) {
      this.closingValue = true
      this.element.setAttribute("closing", "")
      setTimeout(() => {
        this.element.removeAttribute("closing")
        this.closingValue = false
        this.element.close()
        this.dispatch("hidden")
      }, 250)
    }
  }

  cancel(event) {
    event.preventDefault();
    this.close();
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.close()
    }
  }

  delayedCheckScroll() {
    console.log("called");
    afterTransition(this.footerSpacerTarget, true, () => {
      this.checkScroll()
    })
  }

  checkScroll() {
    const scrollTop = this.contentTarget.scrollTop
    const scrollHeight = this.contentTarget.scrollHeight
    const clientHeight = this.contentTarget.clientHeight
    const maxScroll = scrollHeight - clientHeight

    if (scrollHeight > clientHeight && scrollTop < maxScroll) {
      this.footerBorderValue = true
    } else {
      this.footerBorderValue = false
    }
  }
}

