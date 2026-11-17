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
    clearTimeout(this.settleTimeout)
    window.visualViewport.removeEventListener("resize", this.boundCheckVisualViewport)
    document.removeEventListener("blur", this.boundCheckVisualViewport)
  }

  // Moving from one field to the next takes focus away for a moment and
  // swaps one keyboard for another, and the viewport reports the sizes in
  // between. Room that changes under the page while the browser scrolls to
  // the new field makes it jump. So once a keyboard is up, a change waits
  // until it has held for a while; a keyboard coming up applies at once.
  checkVisualViewport() {
    const offset = this.measure()
    clearTimeout(this.settleTimeout)
    if (this.offsetValue > 0 && offset !== this.offsetValue) {
      this.settleTimeout = setTimeout(() => this.apply(this.measure()), 250)
      return
    }
    this.apply(offset)
  }

  // What the keyboard covers, while a field that brings one up has focus.
  measure() {
    if (!this.isKeyboardable(document.activeElement)) return 0
    return window.innerHeight - window.visualViewport.height
  }

  // Two measures for a page to make room with. The offset is what the
  // keyboard covers now. The room is the most it has covered since it came
  // up: one keyboard can give way to a shorter one, and a page that has
  // already scrolled into the room the taller one made would jump back if
  // that room were taken away under it.
  apply(offset) {
    this.offsetValue = offset
    this.room = offset > 0 ? Math.max(this.room || 0, offset) : 0

    document.documentElement.style.setProperty("--visual-viewport-offset", `${this.offsetValue}px`);
    document.documentElement.style.setProperty("--visual-viewport-room", `${this.room}px`);
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

