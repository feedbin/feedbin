import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="selectable"
export default class extends Controller {
  select(event) {
    console.time("select")
    const target = event.currentTarget
    const container = target.closest("[data-selectable-parent]")
    container.querySelectorAll("[data-selected=true]").forEach((element) => {
      element.dataset.selected = "false"
    })
    if (target.dataset.selected === "false") {
      target.dataset.selected = "true"
    }
    console.timeEnd("select")
  }
}
