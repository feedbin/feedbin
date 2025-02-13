import { Controller } from "@hotwired/stimulus"
import { animateHeight } from "helpers"

// Connects to data-controller="add-feed"
export default class extends Controller {
  static targets = ["checkbox", "submit", "resultsBody", "resultsFooter", "searchForm", "searchInput"]

  static values = {
    count: Number,
    selected: Number,
  }

  connect() {
    requestAnimationFrame(() => {
      this.countSelected()
    })

    this.hasResults = false
    this.isClosing = false
    this.subscribeByQueryString()
  }

  countSelected() {
    const count = this.checkboxTargets.filter((input) => input.checked).length
    this.selectedValue = count

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = (count === 0) ? true : false
    }
  }

  clearResults(event) {
    if (!this.hasResults) {
      return
    }

    this.isClosing = true

    const beforeHeight = this.resultsBodyTarget.clientHeight
    const afterHeight = 0

    animateHeight(this.resultsBodyTarget, beforeHeight, afterHeight, () => {
      this.resultsBodyTarget.innerHTML = ""
      this.isClosing = false
      this.dispatch("closed")
    })

    this.resultsFooterTarget.innerHTML = ""
  }

  updateContent(event) {
    this.hasResults = true

    const data = JSON.parse(event.detail.data)
    callback = () => {
      this.resultsBodyTarget.innerHTML = data.body
      this.resultsFooterTarget.innerHTML = data.footer

      const afterHeight = this.resultsBodyTarget.clientHeight
      animateHeight(this.resultsBodyTarget, 0, afterHeight)

      this.countSelected()
    }

    if (this.isClosing) {
      window.addEventListener("add-feed:closed", () => {
        setTimeout(callback, 150)
      }, { once: true })
    } else {
      callback()
    }
  }

  // subscribe via query string support ?subscribe=http://example.com
  static afterLoad(identifier, application) {
    const subscription = window.feedbin.queryString('subscribe')
    if (subscription) {
      requestAnimationFrame(() => {
        const addButton = document.querySelector("[data-behavior~=show_subscribe]")
        addButton.click()
      })
    }
  }

  subscribeByQueryString() {
    const subscription = window.feedbin.queryString('subscribe')
    if (subscription) {
      this.searchInputTarget.value = subscription
      setTimeout(() => {
        // jQuery wrapper needed to submit via rails_ujs
        $(this.searchFormTarget).submit()
      }, 500)
    }
  }
}
