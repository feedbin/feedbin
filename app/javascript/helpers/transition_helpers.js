export function afterTransition(element, condition, callback) {
  let timeout = 0
  if (condition) {
    timeout = parseFloat(getComputedStyle(element).transitionDuration) * 1000
  }
  setTimeout(callback, timeout)
}

export function nextFrame() {
  return new Promise(requestAnimationFrame)
}


export function animateHeight(element, start, end, callback) {
  element.style.height = `${start}px`

  requestAnimationFrame(() => {
    element.style.height = `${end}px`
    element.addEventListener("transitionend", () => {
      element.style.height = ""
      callback()
    }, { once: true })
  })
}
