import { Controller } from "@hotwired/stimulus"
import { afterTransition, afterAnimation, html, animateHeight } from "helpers"

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

    this.clickOrigin = null
    this.dialogOpen = false
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.boundCancel)
    window.removeEventListener("resize", this.boundCheckScroll)
    this.snapContainerTarget.removeEventListener("scroll", this.boundCheckSnapScroll)
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

    if (!this.dialogOpen) {
      return
    }

    this.open(element, event.detail.dialog_id, true)
  }

  open(element, id, update = false) {
    let dataElement = element.querySelector(`template[data-dialog-id=${id}]`)
    if (!dataElement) {
      console.trace(`unknown template`, id)
      return
    }

    const content = dataElement.content.cloneNode(true)
    const beforeHeight = (this.hasContentTarget) ? this.contentTarget.clientHeight : 0

    html(this.dialogContentTarget, content)

    if (update) {
      const afterHeight = this.contentTarget.clientHeight
      animateHeight(this.contentTarget, beforeHeight, afterHeight, true, () => {
        this.checkScroll()
      })
    }

    this.closingValue = false
    this.dialogOpen = true
    this.dialogTarget.showModal()
    this.dispatch("show", { detail: { id: id } })

    // scroll to end of snapContainer to skip
    // blank container above, seems to only matter in Chrome
    this.snapContainerTarget.scrollTo({
      top: this.snapContainerTarget.scrollHeight,
    })

    requestAnimationFrame(() => {
      this.checkScroll()
    })

    afterAnimation(this.dialogTarget, true, () => {
      this.dispatch("shown", { detail: { id: id } })
    })
  }

  close(event = {}, now = false) {
    this.dispatch("willHide")
    this.closingValue = true
    this.dialogOpen = false

    const callback = () => {
      this.dialogTarget.close()
      this.dispatch("hidden")
    }

    if (now) {
      callback()
    } else {
      afterAnimation(this.dialogTarget, true, callback)
    }
  }

  cancel(event) {
    event.preventDefault();
    this.close();
  }

  closeStart(event) {
    this.clickOrigin = event.target
  }

  closeEnd(event) {
    if (event.target === this.dialogTarget && this.clickOrigin === this.dialogTarget) {
      this.close()
    }
    this.clickOrigin = null
  }

  delayedCheckScroll() {
    if (this.hasFooterSpacerTarget) {
      afterTransition(this.footerSpacerTarget, true, () => {
        this.checkScroll()
      })
    }
  }

  checkSnapScroll() {
    // autoclose if snapContainer below 1% of the height
    const scrollTop = this.snapContainerTarget.scrollTop
    const scrollHeight = this.snapContainerTarget.scrollHeight
    const threshold = scrollHeight * 0.01
    if (scrollTop < threshold) {
      this.close({}, true)
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

