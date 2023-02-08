import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers"

// Connects to data-controller="sourceable"
export default class extends Controller {
  static targets = ["source"]

  initialize() {
    this.sourceTargetConnected = debounce(this.sourceTargetConnected.bind(this))
    this.sourceTargetDisconnected = debounce(
      this.sourceTargetDisconnected.bind(this)
    )
  }

  sourceTargetConnected() {
    this.dispatch("source-target-connected")
  }

  sourceTargetDisconnected() {
    this.dispatch("source-target-disconnected")
  }

  selected(event) {
    this.dispatch("selected", {
      detail: event.params.payload,
      target: event.currentTarget,
    })
  }
}
