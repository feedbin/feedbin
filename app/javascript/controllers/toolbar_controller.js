import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"

export default class extends Controller {
  static targets = ["toolbar"]
  static values = {
    section: String,
  }

  connect() {
    this.lastScrollPosition = 0
    this.cssClass = `hide-${this.sectionValue}-toolbar`
  }

  scroll(event) {
    const element = event.target
    const maxScrollHeight = element.scrollHeight - element.offsetHeight
    const currentScrollPosition = element.scrollTop

    if (window.feedbin.shareOpen()) {
      this.show(event)
    } else if (maxScrollHeight < 40) {
      this.show(event)
    } else if (currentScrollPosition <= 0) {
      this.show(event)
    } else if (currentScrollPosition >= maxScrollHeight) {
      this.show(event)
    } else if (currentScrollPosition > this.lastScrollPosition) {
      this.hide(event)
    } else if (currentScrollPosition < this.lastScrollPosition) {
      this.show(event)
    }

    this.lastScrollPosition = currentScrollPosition
  }

  hide() {
    document.body.classList.add(this.cssClass)
  }

  show() {
    document.body.classList.remove(this.cssClass)
  }

  showWithoutAnimation(event) {
    if (this.hasToolbarTarget) {
      this.toolbarTargets.forEach((element) =>
        element.classList.add("no-transition")
      )
      afterTransition(this.toolbarTarget, this.openValue, () => {
        this.toolbarTargets.forEach((element) =>
          element.classList.remove("no-transition")
        )
      })
    }
    this.show(event)
  }

  mousing(event) {
    if (
      document.body.classList.contains(this.cssClass) &&
      window.feedbin.mouseMovingTowardsTop(event, 150)
    ) {
      this.show(event)
    }
  }
}
