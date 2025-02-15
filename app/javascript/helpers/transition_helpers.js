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


export function animateHeight(element, start, end, unsetHeight, callback) {
  element.style.height = `${start}px`

  requestAnimationFrame(() => {
    element.style.height = `${end}px`
    afterTransition(element, true, () => {
      if (unsetHeight) {
        element.style.height = ""
      }
      if (callback) {
        callback()
      }
    })
  })
}
