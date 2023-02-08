import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toggle-checkboxes"
export default class extends Controller {
  static targets = ["checkbox", "includeAll", "actions"]
  static values = {
    includeAllVisible: Boolean,
  }

  toggle(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach((input) => (input.checked = checked))
    this.includeAllVisibleValue = event.target.checked
    if (this.hasIncludeAllTarget && !checked) {
      this.includeAllTarget.checked = false
      this.includeAllTarget.dispatchEvent(new Event("input"))
    }
    this.toggleActions()
  }

  toggleActions() {
    const anyChecked = this.checkboxTargets.find((input) => input.checked)
    this.actionsTarget.disabled = !anyChecked
  }

  includeAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach((input) => {
      if (checked) {
        input.checked = true
      }
      input.disabled = checked
    })
  }
}
