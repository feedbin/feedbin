import { Controller } from "@hotwired/stimulus"
import { afterTransition, hydrate, html } from "helpers"

export default class extends Controller {
  static targets = ["dialog", "dialogContent", "dialogTemplate", "content", "footerSpacer"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    footerBorder: Boolean,
    headerBorder: Boolean,
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
    if (!event?.detail?.dialog_id) {
      console.trace(`dialog_id required for modal`, event)
      return
    }

    let dataElement = document.querySelector(`script[data-dialog-id=${event.detail.dialog_id}]`)

    if (!dataElement) {
      console.trace(`unknown template`, event?.detail?.dialog_id)
      return
    }

    let data = JSON.parse(dataElement.textContent)
    let dialogParts = [
      {
        type: "text",
        selector: "title",
        value: data.title,
      },
      {
        type: "html",
        selector: "body",
        value: data.body,
      },
      {
        type: "html",
        selector: "footer",
        value: data.footer,
      },
    ]

    this.open(dialogParts)
  }

  open(content) {
    const showEvent = this.dispatch("willShow")
    if (!showEvent.defaultPrevented) {
      const dialogTemplate = this.dialogTemplateTarget.content.cloneNode(true)
      html(this.dialogContentTarget, [hydrate(dialogTemplate, content)])

      this.dialogTarget.showModal()
      this.dispatch("show")
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
    if (this.hasFooterSpacerTarget) {
      afterTransition(this.footerSpacerTarget, true, () => {
        this.checkScroll()
      })
    }
  }

  checkScroll() {
    if (!this.hasContentTarget) {
      return
    }
    const scrollTop = this.contentTarget.scrollTop
    const scrollHeight = this.contentTarget.scrollHeight
    const clientHeight = this.contentTarget.clientHeight
    const maxScroll = scrollHeight - clientHeight

    if (scrollTop > 0) {
      this.headerBorderValue = true
    } else {
      this.headerBorderValue = false
    }

    if (scrollHeight > clientHeight && scrollTop < maxScroll) {
      this.footerBorderValue = true
    } else {
      this.footerBorderValue = false
    }
  }
}

