import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--subscriptions"
export default class extends Controller {
  static targets = ["feed", "count"]
  static values = {
    selectedCount: Number
  }

  updateSelection(event) {
    const count = this.feedTargets.filter((input) => input.checked).length
    this.selectedCountValue = count
    this.countTarget.textContent = count
    this.submitForm()
  }

  clearAll(event) {
    this.feedTargets.map((input) => input.checked = false)
    this.selectedCountValue = 0
    this.countTarget.textContent = 0
    this.submitForm()
  }

  submitForm() {
    this.element.requestSubmit()
  }
}
