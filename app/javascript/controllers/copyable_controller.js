import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="expandable"
export default class extends Controller {
  static values = {
    data: String,
    success: Boolean,
  }

  copy(event) {
    navigator.clipboard.writeText(this.dataValue).then(
      () => {
        this.successValue = true
        setTimeout(() => {
          this.successValue = false
        }, 1000)
      },
      () => {
        console.log("failed")
      }
    )
    event.preventDefault()
  }
}
