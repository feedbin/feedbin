import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

// Connects to data-controller="onboarding--main"
export default class extends Controller {
  static targets = ["panel", "viewport", "scrollTrack"]

  static values = {
    step: String,
    animate: Boolean,
    path: String, // path can either be `add` or `import`
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
    if (event.params.setPath) {
      this.pathValue = event.params.panel
    }
    this.goToPanel(panelName)
  }

  back() {
    this.navigate(-1)
  }

  continue() {
    this.navigate(1)
  }

  navigate(direction) {
    const currentIndex = this.panelTargets.findIndex(element => element.dataset.panel === this.stepValue)
    const start = direction > 0 ? currentIndex + 1 : currentIndex - 1
    const end = direction > 0 ? this.panelTargets.length : -1
    const step = direction > 0 ? 1 : -1

    for (let i = start; direction > 0 ? i < end : i > end; i += step) {
      const panel = this.panelTargets[i]
      if (getComputedStyle(panel).display !== "none") {
        this.goToPanel(panel.dataset.panel, true, direction < 0)
        return
      }
    }
  }

  setPath(event) {
    console.log({"this.pathValue": this.pathValue});
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

    console.log({offset});

    afterTransition(this.scrollTrackTarget, true, () => {
      this.animateValue = true
    })
  }
}
