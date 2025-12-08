import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--main"
export default class extends Controller {
  static values = {
    step: String
  }

  connect() {
    console.log("onboarding--main connected");
  }
}
