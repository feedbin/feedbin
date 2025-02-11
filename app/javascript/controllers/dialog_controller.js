import { Controller } from "@hotwired/stimulus"
import { afterTransition, hydrate, html } from "helpers"

export default class extends Controller {
  static targets = ["dialog", "dialogContent", "snapContainer", "content", "footerSpacer"]
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

    // Add scroll event listener for snapContainer
    this.boundCheckSnapScroll = this.checkSnapScroll.bind(this)
    this.snapContainerTarget.addEventListener("scroll", this.boundCheckSnapScroll)

    this.cleanup()
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.boundCancel)
    window.removeEventListener("resize", this.boundCheckScroll)
    this.snapContainerTarget.removeEventListener("scroll", this.boundCheckSnapScroll)
  }

  cleanup() {
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

    this.open(element, event.detail.dialog_id, true)
  }

  open(element, id, update = false) {
    let dataElement = element.querySelector(`template[data-dialog-id=${id}]`)

    if (!dataElement) {
      console.trace(`unknown template`, id)
      return
    }

    this.currentDialogId = id

    if (!update) {
      this.writeContent(dataElement, update)
    }

    this.dispatch("show")
    this.closingValue = false
    this.dialogTarget.showModal()

    // scroll to end of snapContainer to skip
    // blank container above
    this.snapContainerTarget.scrollTo({
      top: this.snapContainerTarget.scrollHeight,
    })

    // setTimeout needs to match animation
    // timing from tailwind.config.js slide-in
    setTimeout(() => {
      if (update) {
        this.writeContent(dataElement, update)
      }
      this.dispatch("shown")
    }, 300)
  }

  writeContent(element, update) {
    const content = element.content.cloneNode(true)
    const beforeHeight = (this.hasContentTarget) ? this.contentTarget.clientHeight : 0

    html(this.dialogContentTarget, content)

    if (update) {
      this.animateUpdate(beforeHeight)
    }

    setTimeout(() => {
      this.checkScroll()
    }, 0)
  }

  animateUpdate(beforeHeight) {
    const afterHeight = this.contentTarget.clientHeight
    this.contentTarget.style.height = `${beforeHeight}px`

    requestAnimationFrame(() => {
      this.contentTarget.style.height = `${afterHeight}px`
      this.contentTarget.addEventListener("transitionend", () => {
        this.contentTarget.style.height = ""
        this.checkScroll()
      }, { once: true })
    })
  }

  close(now = false) {
    this.dispatch("willHide")
    this.closingValue = true
    this.cleanup()

    // setTimeout needs to match animation
    // timing from tailwind.config.js slide-out
    const timeout = (now === true) ? 0 : 250
    setTimeout(() => {
      this.dialogTarget.close()
      this.dispatch("hidden")
    }, timeout)
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

  checkSnapScroll() {
    // autoclose if snapContainer below 5% of the height
    const scrollTop = this.snapContainerTarget.scrollTop
    const scrollHeight = this.snapContainerTarget.scrollHeight
    const threshold = scrollHeight * 0.01
    if (scrollTop < threshold) {
      this.close(true)
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

