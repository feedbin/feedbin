import { Controller } from "@hotwired/stimulus"
import { afterTransition, hydrate, html } from "helpers"

export default class extends Controller {
  static targets = ["dialog", "dialogTemplate", "content", "footerSpacer", "contentTemplate"]
  static outlets = ["expandable"]
  static values = {
    closing: Boolean,
    footerBorder: Boolean,
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
    if (!event?.detail?.purpose || !event?.detail?.data) {
      console.trace(`purpose and data required for modal`, event)
      return
    }

    let contentTemplate = this.contentTemplateTargets.find((template) => template.dataset.purpose === event.detail.purpose)
    if (!contentTemplate) {
      console.trace(`unknown template`, event?.detail?.purpose)
      return
    }

    let content = contentTemplate.content.cloneNode(true)
    let hydratedContent = hydrate(content, event.detail.data)
    let dialogParts = [
      {
        type: "text",
        selector: "title",
        value: hydratedContent.querySelector("[data-dialog-content=title]").textContent,
      },
      {
        type: "html",
        selector: "body",
        value: [...hydratedContent.querySelector("[data-dialog-content=body]").children],
      },
      {
        type: "html",
        selector: "footer",
        value: [...hydratedContent.querySelector("[data-dialog-content=footer]").children],
      },
    ]

    this.open(dialogParts)
  }

  open(content) {
    const showEvent = this.dispatch("willShow")
    if (!showEvent.defaultPrevented) {
      const dialogTemplate = this.dialogTemplateTarget.content.cloneNode(true)
      html(this.dialogTarget, [hydrate(dialogTemplate, content)])

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

    if (scrollHeight > clientHeight && scrollTop < maxScroll) {
      this.footerBorderValue = true
    } else {
      this.footerBorderValue = false
    }
  }
}

