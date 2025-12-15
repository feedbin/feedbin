import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="onboarding--main"
export default class extends Controller {
  static targets = ["panel", "viewport", "scrollTrack"]

  static values = {
    step: String,
    animate: Boolean
  }

  connect() {
    this.boundResize = this.goToPanel.bind(this)
    window.visualViewport.addEventListener("resize", () => {
      this.boundResize(this.stepValue, false)
    })
  }

  disconnect() {
    window.visualViewport.removeEventListener("resize", this.boundResize)
  }

  panelSelected(event) {
    const panelName = event.params.panel
    this.goToPanel(panelName)
  }

  goToPanel(panelName, animate = true) {
    if (!animate) {
      this.animateValue = false
    }

    this.stepValue = panelName
    const panelIndex = this.panelTargets.findIndex(element => element.dataset.panel === panelName);
    const panelElement = this.panelTargets[panelIndex]
    const offset = -panelElement.offsetLeft
    this.scrollTrackTarget.style.transform = `translateX(${offset}px)`;

    afterTransition(this.scrollTrackTarget, true, () => {
      this.animateValue = true
    })
  }
}
