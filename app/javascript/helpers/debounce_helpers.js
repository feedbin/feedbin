export function debounce(callback, delay = 10) {
  let timeoutId = null

  return (...args) => {
    const debouncedCallback = () => callback.apply(this, args)
    clearTimeout(timeoutId)
    timeoutId = setTimeout(debouncedCallback, delay)
  }
}

export function throttle(callback, delay = 100) {
  let timeoutId = null

  return (...args) => {
    if (!timeoutId) {
      callback(...args)
      timeoutId = setTimeout(() => (timeoutId = null), delay)
    }
  }
}
