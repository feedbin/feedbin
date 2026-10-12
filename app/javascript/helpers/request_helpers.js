// fetch for Stimulus controllers, with the two headers jquery_ujs adds to
// jQuery requests: the CSRF token, and the marker Rails reads as xhr?.
// Throws on a response that is not 2xx, so callers handle every failure in
// one place. feedbin.activeRequests counts the requests in flight; the system
// tests wait on it the way they wait on jQuery.active.
export async function request(url, { method = "GET", accept = "application/json", signal } = {}) {
  const feedbin = window.feedbin
  feedbin.activeRequests = (feedbin.activeRequests ?? 0) + 1
  try {
    const response = await fetch(url, {
      method,
      signal,
      credentials: "same-origin",
      headers: {
        "Accept": accept,
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest",
      },
    })
    if (!response.ok) {
      throw new Error(`${method} ${url} failed with ${response.status}`)
    }
    return response
  } finally {
    feedbin.activeRequests -= 1
  }
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
}
