import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="expandable"
export default class extends Controller {
  static values = {
    open: Boolean,
  }

  toggle() {
    this.openValue = !this.openValue
  }
}
