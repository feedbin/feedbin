import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="expandable"
export default class extends Controller {
  static targets = ["transitionContainer"]
  static values = {
    open: Boolean,
    visible: Boolean,
  }

  toggle(event) {
    if (event && event.target.type === "radio") {
      this.openValue = !(event.params.toggleTarget)
    }

    this.openValue = !this.openValue
    afterTransition(this.transitionContainerTarget, this.openValue, () => {
      this.visibleValue = this.openValue
    })
  }
}
