import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="add--footer"
export default class extends Controller {
  static targets = ["submit"]

  static values = {
    selected: Number
  }

  connect() {
    console.log("add--footer connected");
  }

  update(event) {
    const count = event.detail.count
    this.selectedValue = count
    if (count > 0) {
      this.submitTarget.disabled = false
    }
    console.log("update", event);
  }
}
