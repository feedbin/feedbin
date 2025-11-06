import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--subscriptions"
export default class extends Controller {
  static targets = ["feed", "count"]
  static values = {
    selectedCount: Number
  }

  connect() {
    console.log("onboarding--subscriptions connected");
  }

  updateSelection(event) {
    const count = this.feedTargets.filter((input) => input.checked).length
    this.selectedCountValue = count
    this.countTarget.textContent = count
  }

  clearAll(event) {
    this.feedTargets.map((input) => input.checked = false)
    this.updateSelection()
  }
}
