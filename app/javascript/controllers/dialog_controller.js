import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "content", "headerBorder", "footerBorder"]
  static values = {
    closing: Boolean,
    headerBorder: Boolean,
    footerBorder: Boolean,
  }

  connect() {
    this.checkScroll()
    console.log(this.element);
    window.addEventListener("resize", () => this.checkScroll())
  }

  open() {
    const showEvent = this.dispatchDialogEvent("dialog:willShow")
    this.element.showModal()
    this.checkScroll()

    this.element.addEventListener(
      "animationend", () => {
        this.dispatchDialogEvent("dialog:shown")
      },
      { once: true }
    )
  }

  close() {
    const hideEvent = this.dispatchDialogEvent("dialog:willHide")

    if (!hideEvent.defaultPrevented) {
      this.closingValue = true
      this.element.setAttribute("closing", "")
      this.element.addEventListener(
        "animationend", () => {
          this.element.removeAttribute("closing")
          this.closingValue = false
          this.element.close()
          this.dispatchDialogEvent("dialog:hidden")
        },
        { once: true }
      )
    }
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.close()
    }
  }

  checkScroll() {
    const scrollTop = this.contentTarget.scrollTop
    const scrollHeight = this.contentTarget.scrollHeight
    const clientHeight = this.contentTarget.clientHeight
    const maxScroll = scrollHeight - clientHeight

    // if (scrollTop > 0) {
    //   this.headerBorderValue = true
    // } else {
    //   this.headerBorderValue = false
    // }

    if (scrollHeight > clientHeight && scrollTop < maxScroll) {
      this.footerBorderValue = true
    } else {
      this.footerBorderValue = false
    }
  }

  dispatchDialogEvent(eventName) {
    const event = new CustomEvent(eventName, {
      bubbles: true,
      cancelable: true,
      detail: {
        dialogId: this.element.id,
      },
    })
    document.dispatchEvent(event)
    return event
  }
}

