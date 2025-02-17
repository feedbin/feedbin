import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="search-form"
export default class extends Controller {
  static targets = ["query", "sortLabel", "sortOption"]
  static outlets = ["search-token"]
  static values = {
    visible: Boolean,
    foreground: Boolean,
    optionsVisible: Boolean,
  }

  connect() {
    this.element[this.identifier] = this
  }

  show(event) {
    this.toggle(event, true)
  }

  hide(event) {
    this.toggle(event, false)
  }

  toggle(event, visible) {
    visible = typeof visible === "undefined" ? !this.visibleValue : visible
    this.visibleValue = visible
    if (!this.visibleValue) {
      this.optionsVisibleValue = false
    } else {
      this.queryTarget.focus()
      this.searchTokenOutlet.buildJumpable()
    }

    if (!this.visibleValue && this.hasSearchTokenOutlet) {
      this.searchTokenOutlet.hideSearch(event)
    }

    afterTransition(this.element, this.visibleValue, () => {
      this.foregroundValue = this.visibleValue
    })
  }

  showSearchControls(event) {
    this.optionsVisibleValue = true

    document.body.classList.remove("nothing-selected", "entry-selected")
    document.body.classList.add("feed-selected")

    window.feedbin.markReadData = {
      type: "search",
      data: event.detail.query,
      message: event.detail.message,
    }
  }

  changeSearchSort(event) {
    let sortOption = event.target.dataset.sortOption
    let value = this.queryTarget.value
    value = value.replace(
      /\s*?(sort:\s*?asc|sort:\s*?desc|sort:\s*?relevance)\s*?/,
      ""
    )

    if (sortOption !== "desc") {
      value = `${value} sort:${sortOption}`
    }

    this.queryTarget.value = value
    this.sortLabelTarget.textContent = event.target.textContent

    let form = this.queryTarget.closest("form")

    window.$(form).submit()
  }
}
