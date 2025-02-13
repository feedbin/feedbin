import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="add--form"
export default class extends Controller {
  static targets = ["checkbox", "submit"]

  static values = {
    count: Number,
    selected: Number,
  }

  connect() {
    console.log("add--form connected");
    requestAnimationFrame(() => {
      this.countSelected()
    })
  }

  countSelected() {
    console.log("called");
    const count = this.checkboxTargets.filter((input) => input.checked).length
    this.dispatch("selectionChanged", {detail: { count: count }})
  }

  update(event) {
    const count = event.detail.count
    this.selectedValue = count
    this.submitTarget.disabled = (count === 0) ? true : false
  }
}
