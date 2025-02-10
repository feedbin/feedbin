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
