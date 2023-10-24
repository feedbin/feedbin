import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="expandable-container"
export default class extends Controller {
  static targets = ["transitionContainer"]
  static values = {
    open: Boolean,
    visible: Boolean,
  }

  toggle() {
    this.openValue = !this.openValue
    afterTransition(this.transitionContainerTarget, this.openValue, () => {
      this.visibleValue = this.openValue
    })
  }
}
