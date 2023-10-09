import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tabs"
export default class extends Controller {
  static targets = ["tabContent", "tabButton"]

  select(event) {
    const selectedTab = event.params.tab;
    this.tabContentTargets.forEach((element, index) => {
      element.dataset["ui"] = (selectedTab === index) ? "selected" : ""
    })
    this.tabButtonTargets.forEach((element, index) => {
      element.dataset["ui"] = (selectedTab === index) ? "selected" : ""
    })
  }
}
