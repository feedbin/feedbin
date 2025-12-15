import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="onboarding--main"
export default class extends Controller {
  static targets = ["panel", "viewport", "scrollTrack"]

  static values = {
    step: String
  }

  connect() {
    this.boundResize = this.goToPanel.bind(this)
    window.visualViewport.addEventListener("resize", () => {
      this.boundResize(this.stepValue, true)
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
    console.log({panelName, animate});
    this.stepValue = panelName

    console.log(this.stepValue);

    const panelIndex = this.panelTargets.findIndex(element => element.dataset.panel === panelName);
    const panelElement = this.panelTargets[panelIndex]
    const viewport = this.viewportTarget

    const panelElementRect = panelElement.getBoundingClientRect()
    const viewportRect = viewport.getBoundingClientRect()
    const offset = (panelElementRect.left - viewportRect.left) * -1

    this.scrollTrackTarget.style.transform = `translateX(${offset}px)`;


    console.log(offset);

    console.log(panelElement);
  }
}
