import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--subscriptions"
export default class extends Controller {
  static values = {
  }

  connect() {
    console.log("onboarding--subscriptions connected");
  }
}
