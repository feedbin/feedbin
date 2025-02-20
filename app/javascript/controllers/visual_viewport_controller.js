import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    offset: Number,
  }

  connect() {
    this.checkVisualViewport()
    this.boundCheckVisualViewport = this.delayedCheck.bind(this)
    window.visualViewport.addEventListener("resize", this.boundCheckVisualViewport)
    document.addEventListener("blur", this.boundCheckVisualViewport, true)
  }

  disconnect() {
    window.visualViewport.removeEventListener("resize", this.boundCheckVisualViewport)
    document.removeEventListener("blur", this.boundCheckVisualViewport)
  }

  checkVisualViewport() {
    const offsetHeight = window.innerHeight - window.visualViewport.height
    const inputActive = this.isKeyboardable(document.activeElement)
    this.offsetValue = (!inputActive) ? 0 : offsetHeight

    document.documentElement.style.setProperty("--visual-viewport-offset", `${this.offsetValue}px`);
    this.dispatch("change", { detail: { offset: this.offsetValue } })
  }

  delayedCheck() {
    // When switching between fields, blur is called
    // and the other field does not have focus yet
    setTimeout(()=>{
      this.checkVisualViewport()
    }, 10)
  }

  isKeyboardable(element) {
    if (element.tagName === "TEXTAREA") return true;
    if (element.tagName === "INPUT") {
      const textTypes = ["text", "password", "email", "search", "tel", "url", null, ""];
      return textTypes.includes(element.type.toLowerCase());
    }
    if (element.isContentEditable) return true;
    return false;
  }
}

