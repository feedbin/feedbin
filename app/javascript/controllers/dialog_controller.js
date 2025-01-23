import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

export default class extends Controller {
  static targets = ["content", "headerBorder", "footerBorder", "footer"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    headerBorder: Boolean,
    footerBorder: Boolean,
    purpose: String
  }

  connect() {
    document.addEventListener("keydown", this.closeHandler.bind(this))
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeHandler.bind(this))
  }

  connect() {
    // remap cancel to custom cancel
    this.boundCancel = this.cancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)

    this.checkScroll()
    this.boundCheckScroll = this.checkScroll.bind(this)
    window.addEventListener("resize", this.boundCheckScroll)

    this.checkVisualViewport()
    this.boundCheckVisualViewport = this.checkVisualViewport.bind(this)
    window.visualViewport.addEventListener("resize", this.boundCheckVisualViewport)

    document.addEventListener("blur", this.boundCheckVisualViewport, true)
  }

  disconnect() {
    this.element.removeEventListener("cancel", this.boundCancel)
    window.removeEventListener("resize", this.boundCheckScroll)
    window.visualViewport.removeEventListener("resize", this.boundCheckVisualViewport)
    document.removeEventListener("blur", this.boundCheckVisualViewport)
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

  checkVisualViewport() {
    const keyboardHeight = window.innerHeight - window.visualViewport.height
    const inputActive = this.isKeyboardable(document.activeElement)

    if (keyboardHeight === 0 || !inputActive) {
      this.footerTarget.style.height = `env(safe-area-inset-bottom)`
    } else {
      this.footerTarget.style.height = `${keyboardHeight}px`
    }
    afterTransition(this.footerTarget, true, () => {
      this.checkScroll()
    })
  }

  isKeyboardable(element) {
      // Check if it's a textarea
      if (element.tagName === 'TEXTAREA') return true;

      // Check if it's an input with text-accepting type
      if (element.tagName === 'INPUT') {
          const textTypes = [
              'text',
              'password',
              'email',
              'search',
              'tel',
              'url',
              null,
              ''
          ];
          return textTypes.includes(element.type.toLowerCase());
      }

      // Check if it's contenteditable
      if (element.isContentEditable) return true;

      return false;
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

