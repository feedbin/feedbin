import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

export default class extends Controller {
  static targets = ["dialog", "contentTemplate", "content", "footerSpacer", "footerBorder"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    footerBorder: Boolean,
    purpose: String,
  }

  connect() {
    // remap cancel to custom cancel
    this.boundCancel = this.cancel.bind(this)
    this.dialogTarget.addEventListener("cancel", this.boundCancel)

    this.boundCheckScroll = this.checkScroll.bind(this)
    window.addEventListener("resize", this.boundCheckScroll)
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.boundCancel)
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
      const contentTemplate = this.contentTemplateTarget.content.cloneNode(true)
      this.dialogTarget.innerHTML = ""
      this.dialogTarget.append(contentTemplate)

      this.dialogTarget.showModal()
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
      this.dialogTarget.setAttribute("closing", "")
      setTimeout(() => {
        this.dialogTarget.removeAttribute("closing")
        this.closingValue = false
        this.dialogTarget.close()
        this.dispatch("hidden")
      }, 250)
    }
  }

  cancel(event) {
    event.preventDefault();
    this.close();
  }

  clickOutside(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  delayedCheckScroll() {
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

