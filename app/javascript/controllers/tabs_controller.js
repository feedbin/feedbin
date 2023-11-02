import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tabs"
export default class extends Controller {
  static targets = ["tabContent", "tabButton", "indicator"]

  connect() {
    this.indicator(this.tabButtonTarget)
  }

  select(event) {
    const selectedIndex = event.params.tab;

    this.indicator(this.tabButtonTargets[selectedIndex])

    this.tabContentTargets.forEach((element, index) => {
      element.dataset["ui"] = (selectedIndex === index) ? "selected" : ""
    })
    this.tabButtonTargets.forEach((element, index) => {
      element.dataset["ui"] = (selectedIndex === index) ? "selected" : ""
    })
  }

  indicator(element) {
    this.indicatorTarget.style.width = `${element.offsetWidth}px`
    this.indicatorTarget.style.left = `${element.offsetLeft}px`
  }
}
