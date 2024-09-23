export class Layout {
  static get oneUp() {
    return document.body.classList.contains("one-up")
  }
  static get twoUp() {
    return document.body.classList.contains("two-up")
  }
  static get threeUp() {
    return document.body.classList.contains("three-up")
  }
  static get fullScreen() {
    return window.feedbin.isFullScreen()
  }
}

export const Config = Object.freeze({
    noTransitionClass: "no-transition",
});