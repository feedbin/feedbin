import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="add-feed"
export default class extends Controller {
  static targets = ["subscribeSubmitButton", "searchSubmitButton", "checkbox", "resultsBody", "resultsFooter", "searchForm", "searchInput"]

  static values = {
    count: Number,
    selected: Number,
    open: Boolean,
  }

  static outlets = ["expandable"]

  #clearing = null

  connect() {
    requestAnimationFrame(() => {
      this.countSelected()
    })
    this.autofocus()
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

    this.clearing = new Promise((resolve, reject) => {
      const callback = () => {
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
        this.expandableOutlet.toggle()
        afterTransition(this.expandableOutlet.transitionContainerTarget, true, () => {
          setTimeout(callback, 150)
        })
      } else {
        callback()
      }
    });
  }

  async updateContent(event) {
    const callback = () => {
      const data = JSON.parse(event.detail.data)

      if (window.matchMedia("(pointer:coarse)").matches) {
        this.searchInputTarget.blur()
      }

      this.openValue = true
      this.resultsBodyTarget.innerHTML = data.body
      this.resultsFooterTarget.innerHTML = data.footer
      this.expandableOutlet.toggle()

      afterTransition(this.expandableOutlet.transitionContainerTarget, true, () => {
        this.countSelected()
        this.searchSubmitButtonTarget.disabled = false
      })
    }

    if (this.clearing) {
      await this.clearing
    }

    callback()
  }

  autofocus(event) {
    if (window.matchMedia("(pointer:fine)").matches) {
      this.searchInputTarget.focus()
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
        window.$(this.searchFormTarget).submit()
      }, 500)
    }
  }
}
