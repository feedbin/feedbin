import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--main"
export default class extends Controller {
  static values = {
  }

  connect() {
    console.log("onboarding--main connected");
  }
}
