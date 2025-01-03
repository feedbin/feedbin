import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "headerBorder", "footerBorder"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    headerBorder: Boolean,
    footerBorder: Boolean,
    purpose: String
  }

  connect() {
    this.checkScroll()
    window.addEventListener("resize", () => this.checkScroll())

    this.boundCancel = this.cancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)
  }

  disconnect() {
    this.element.removeEventListener("cancel", this.boundCancel)
  }

  openWithPurpose(event) {
    console.log(event);
    console.log(this.purposeValue);
    if (event?.detail?.purpose == this.purposeValue) {
      console.log("yes");
      this.open()
    }
  }

  open() {
    const showEvent = this.dispatch("willShow")
    if (!showEvent.defaultPrevented) {
      this.element.showModal()
      this.checkScroll()
      this.element.addEventListener(
        "animationend", () => {
          this.dispatch("shown")
        },
        { once: true }
      )
    }
  }

  close() {
    const hideEvent = this.dispatch("willHide")

    if (!hideEvent.defaultPrevented) {
      this.closingValue = true
      this.element.setAttribute("closing", "")
      this.element.addEventListener(
        "animationend", () => {
          this.element.removeAttribute("closing")
          this.closingValue = false
          this.element.close()
          this.dispatch("hidden")
        },
        { once: true }
      )
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
}

