import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="add--form"
export default class extends Controller {
  static targets = ["checkbox"]

  static values = {
    count: Number
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
}
