import { Controller } from "@hotwired/stimulus"
import { animateHeight, afterTransition } from "helpers"

// Connects to data-controller="add-feed"
export default class extends Controller {
  static targets = ["subscribeSubmitButton", "searchSubmitButton", "checkbox", "resultsBody", "resultsFooter", "searchForm", "searchInput", "heightContainer"]

  static values = {
    count: Number,
    selected: Number,
    open: Boolean,
  }

  #clearing = null

  connect() {
    requestAnimationFrame(() => {
      this.countSelected()
    })

    this.subscribeByQueryString()
  }

  countSelected() {
    const count = this.checkboxTargets.filter((input) => input.checked).length
    this.selectedValue = count

    if (this.hasSubscribeSubmitButtonTarget) {
      this.subscribeSubmitButtonTarget.disabled = (count === 0) ? true : false
    }
  }

  clearResults(event) {
    this.searchSubmitButtonTarget.disabled = true
    if (this.hasSubscribeSubmitButtonTarget) {
      this.subscribeSubmitButtonTarget.disabled = true
    }

    const beforeHeight = this.resultsBodyTarget.clientHeight
    const afterHeight = 0

    this.clearing = new Promise((resolve, reject) => {
      callback = () => {
        if (event.detail?.error) {
          this.searchSubmitButtonTarget.disabled = false
          this.resultsBodyTarget.innerHTML = ""
          this.resultsFooterTarget.innerHTML = ""
        }
        resolve()
        this.clearing = null
      }

      if (this.openValue) {
        this.openValue = false
        animateHeight(this.heightContainerTarget, beforeHeight, afterHeight, false, () => {
          setTimeout(callback, 150)
        })
      } else {
        callback()
      }
    });
  }

  async updateContent(event) {
    const callback = () => {
      this.openValue = true

      const data = JSON.parse(event.detail.data)

      this.resultsBodyTarget.innerHTML = data.body
      this.resultsFooterTarget.innerHTML = data.footer

      const afterHeight = this.resultsBodyTarget.clientHeight
      animateHeight(this.heightContainerTarget, 0, afterHeight, true)

      afterTransition(this.heightContainerTarget, true, () => {
        this.countSelected()
        this.searchSubmitButtonTarget.disabled = false
      })
    }

    if (this.clearing) {
      await this.clearing
    }

    callback()
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
