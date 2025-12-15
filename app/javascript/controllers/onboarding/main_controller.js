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

  back() {
    const currentIndex = this.panelTargets.findIndex(element => element.dataset.panel === this.stepValue)

    for (let i = currentIndex - 1; i >= 0; i--) {
      const panel = this.panelTargets[i]
      if (getComputedStyle(panel).display !== "none") {
        this.goToPanel(panel.dataset.panel, true, true)
        return
      }
    }
  }

  goToPanel(panelName, animate = true, back = false) {
    if (!animate) {
      this.animateValue = false
    }

    afterTransition(this.scrollTrackTarget, back, () => {
      this.stepValue = panelName
    })

    const panelIndex = this.panelTargets.findIndex(element => element.dataset.panel === panelName)
    const panelElement = this.panelTargets[panelIndex]
    const offset = -panelElement.offsetLeft
    this.scrollTrackTarget.style.transform = `translateX(${offset}px)`

    afterTransition(this.scrollTrackTarget, true, () => {
      this.animateValue = true
    })
  }
}
