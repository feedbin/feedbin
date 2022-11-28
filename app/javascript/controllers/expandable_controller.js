import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="expandable"
export default class extends Controller {
  static targets = ["container", "content"];
  static values = {
    open: Boolean
  }

  toggle(event) {
    this.openValue = !this.openValue;
    const height = this.openValue ? this.contentTarget.getBoundingClientRect().height : 0
    this.containerTarget.style["max-height"] = `${height}px`
    const tabTargets = this.contentTarget.querySelectorAll("[tabindex]")

    tabTargets.forEach((element) => {
      element.tabIndex = this.openValue ? "0" : "-1"
    })
  }
}
