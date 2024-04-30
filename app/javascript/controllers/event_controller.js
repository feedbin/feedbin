import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="event"
// data-event-identifier-param
// data-event-payload-param
export default class extends Controller {
  dispatch(event) {
    const custom = new CustomEvent(
      event.params.identifier,
      event.params.payload
    )
    window.dispatchEvent(custom)
  }
}
