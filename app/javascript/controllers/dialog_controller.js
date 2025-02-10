import { Controller } from "@hotwired/stimulus"
import { afterTransition, hydrate, html } from "helpers"

export default class extends Controller {
  static targets = ["dialog", "dialogContent", "dialogTemplate", "content", "footerSpacer"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    footer: Boolean,
    footerBorder: Boolean,
    headerBorder: Boolean,
  }

  connect() {
    // remap cancel to custom cancel
    this.boundCancel = this.cancel.bind(this)
    this.dialogTarget.addEventListener("cancel", this.boundCancel)

    this.boundCheckScroll = this.checkScroll.bind(this)
    window.addEventListener("resize", this.boundCheckScroll)

    this.cleanup()
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.boundCancel)
    window.removeEventListener("resize", this.boundCheckScroll)
  }

  cleanup() {
    this.isOpen = false
    this.isLoaded = false
    this.currentDialogId = null
  }

  openWithPurpose(event) {
    let requestedDialog = event?.detail?.dialog_id
    if (!requestedDialog) {
      console.trace(`dialog_id required for modal`, event)
      return
    }
    this.open(document, requestedDialog)
  }

  updateContent(event) {
    if (!event?.detail?.dialog_id || !event?.detail?.data) {
      console.trace(`dialog_id and datarequired for dialog`, event)
      return
    }

    let element = document.createElement("div")
    element.innerHTML = event.detail.data

    this.open(element, event.detail.dialog_id, !!event?.detail?.wait)
  }

  open(element, id, wait = false) {
    let dataElement = element.querySelector(`script[data-dialog-id=${id}]`)

    if (!dataElement) {
      console.trace(`unknown template`, id)
      return
    }

    this.currentDialogId = id

    let data = JSON.parse(dataElement.textContent)
    let content = [
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

    if (data.footer === "") {
      this.footerValue = false
    } else {
      this.footerValue = true
    }

    const showEvent = this.dispatch("willShow")
    if (!showEvent.defaultPrevented) {
      if (!wait) {
        this.writeContent(content)
      }
      this.isOpen = true
      this.dialogTarget.showModal()
      this.dispatch("show")

      setTimeout(() => {
        if (wait) {
          this.writeContent(content)
        }
        this.dispatch("shown")
        this.isLoaded = true
      }, 350)
    }
  }

  writeContent(content) {
    const dialogTemplate = this.dialogTemplateTarget.content.cloneNode(true)
    html(this.dialogContentTarget, [hydrate(dialogTemplate, content)])
    setTimeout(() => {
      this.checkScroll()
    }, 0)
  }

  close() {
    const hideEvent = this.dispatch("willHide")

    if (!hideEvent.defaultPrevented) {
      this.closingValue = true
      this.dialogTarget.setAttribute("closing", "")
      this.cleanup()
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

