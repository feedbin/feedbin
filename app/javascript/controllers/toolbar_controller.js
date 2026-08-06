import { Controller } from "@hotwired/stimulus"
import { afterTransition } from "helpers"
import { Layout, Config } from "helpers"

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
    if (!this.shouldRun()) {
      return
    }

    const element = event.target
    const maxScrollHeight = element.scrollHeight - element.offsetHeight
    const currentScrollPosition = element.scrollTop

    if (window.feedbin.shareOpen()) {
      this.show(event)
    } else if (maxScrollHeight < 44) {
      this.show(event)
    } else if (currentScrollPosition <= 0) {
      this.show(event)
    } else if (currentScrollPosition >= maxScrollHeight && Layout.oneUp) {
      this.show(event)
    } else if (currentScrollPosition >= maxScrollHeight) {
      this.hide(event)
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

  shouldRun() {
    if (Layout.oneUp || Layout.fullScreen) {
      return true
    }
    return false
  }

  showWithoutAnimation(event) {
    if (this.hasToolbarTarget) {
      // Whether there is a transition to wait out: the toolbar is hidden now
      // and show() is about to reveal it. This read this.openValue, which the
      // controller does not declare, so it was always undefined -- the
      // no-transition class was removed synchronously, before show() ran, and
      // the method did nothing the plain show() does not.
      const hidden = document.body.classList.contains(this.cssClass)
      this.toolbarTargets.forEach((element) =>
        element.classList.add(Config.noTransitionClass)
      )
      afterTransition(this.toolbarTarget, hidden, () => {
        this.toolbarTargets.forEach((element) =>
          element.classList.remove(Config.noTransitionClass)
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
