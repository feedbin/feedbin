import { Controller } from "@hotwired/stimulus"
import { request, userTitle } from "helpers"

// Connects to data-controller="entry-toolbar"
//
// The page has one entry toolbar. feedbin.showEntry sends the toolbar data of
// each entry it opens in an entry-toolbar:show event, and this controller
// fills the toolbar from it. The values hold the state of the open entry, and
// the CSS reads them from their data attributes.
//
// Every action reads the entry id when it starts, so a request that is still
// open when another entry opens applies to the entry it started on.
export default class extends Controller {
  static targets = ["header", "feedLink", "sourceLink"]

  static values = {
    entryId: Number,
    feedId: Number,
    starred: Boolean,
    read: Boolean,
    extract: Boolean,
    loading: Boolean,
    pages: Boolean,
    subscribed: Boolean,
    starredUrl: String,
    unreadUrl: String,
    extractUrl: String,
    deleteUrl: String,
    stickyUrl: String,
    editSubscriptionUrl: String,
  }

  // A full page load of /entries/:id calls feedbin.showEntry from a jQuery
  // ready handler, which can run before Stimulus connects this controller.
  // Its entry-toolbar:show event, and the automatic extract that
  // feedbin.readability() sends after it, then had no listener. Do both now.
  connect() {
    const feedbin = window.feedbin
    const entry = feedbin.selectedEntry && feedbin.entries[feedbin.selectedEntry.id]
    if (entry?.toolbar && !this.entryIdValue) {
      this.show({ detail: entry.toolbar })
      feedbin.readability()
    }
  }

  // detail is null when no entry is open, or when the entry came from a
  // server without toolbar data. Then every action does nothing.
  show(event) {
    const data = event.detail
    if (!data) {
      this.clear()
      return
    }

    const feedbin = window.feedbin
    this.entryIdValue = data.id
    this.feedIdValue = data.feed_id
    this.pagesValue = data.pages
    this.subscribedValue = data.subscribed
    this.starredValue = feedbin.Counts.get().isStarred(data.id)
    // Opening an entry marks it read.
    this.readValue = true
    this.extractValue = false
    this.loadingValue = false

    this.headerTargets.forEach((header) => {
      header.innerHTML = data.favicon
      header.append(this.titleElement(data))
    })
    this.feedLinkTarget.href = this.feedUrl(this.editSubscriptionUrlValue, data.feed_id)
    this.sourceLinkTarget.value = data.url

    this.closeDropdowns()

    feedbin.selectedEntryData = data
    feedbin.prepareShareMenu(data)
    feedbin.faviconColors(window.$(this.element))
  }

  toggleStarred() {
    const id = this.entryIdValue
    if (!id) return

    this.starredValue = window.feedbin.countsBehavior.toggleStarred(id, this.feedIdValue)
    request(this.entryUrl(this.starredUrlValue, id), { method: "POST" }).catch(() => {})
  }

  toggleRead() {
    const id = this.entryIdValue
    if (!id) return

    this.readValue = window.feedbin.countsBehavior.toggleRead(id, this.feedIdValue)
    request(this.entryUrl(this.unreadUrlValue, id), { method: "POST" }).catch(() => {})
  }

  // feedbin.readability() sends {automatic: true} for a feed with sticky
  // extract on; only a press by the user flips that setting.
  toggleExtract(event) {
    const id = this.entryIdValue
    if (!id) return
    const feedbin = window.feedbin

    if (event?.detail?.automatic !== true) {
      this.toggleSticky(this.feedIdValue)
    }

    if (this.loadingValue) {
      feedbin.readabilityXHR?.abort()
      feedbin.readabilityXHR = null
      this.loadingValue = false
      this.extractValue = false
      feedbin.changeContentView("default")
    } else if (this.extractValue) {
      this.extractValue = false
      feedbin.changeContentView(feedbin.previousContentView)
    } else if (id in feedbin.extractCache) {
      this.extractSlot(id).html(feedbin.extractCache[id])
      feedbin.formatEntryContent(id, false, false)
      feedbin.changeContentView("extract")
      this.extractValue = true
    } else {
      this.extract(id)
    }
  }

  // feedbin.formatEntryContent aborts feedbin.readabilityXHR when another
  // entry opens. An AbortController answers to the same abort().
  async extract(id) {
    const feedbin = window.feedbin
    const abort = new AbortController()
    feedbin.readabilityXHR = abort
    this.loadingValue = true
    this.extractValue = true

    let html
    try {
      const url = `${this.entryUrl(this.extractUrlValue, id)}?extract=true`
      const response = await request(url, { accept: "text/html", signal: abort.signal })
      html = await response.text()
    } catch {
      if (abort.signal.aborted || this.entryIdValue !== id) return
      feedbin.readabilityXHR = null
      this.loadingValue = false
      this.extractValue = false
      feedbin.changeContentView("default")
      return
    }
    if (abort.signal.aborted || this.entryIdValue !== id) return

    // Before formatEntryContent, which aborts any request it still finds.
    feedbin.readabilityXHR = null
    this.loadingValue = false
    feedbin.extractCache[id] = html
    this.extractSlot(id).html(html)
    feedbin.changeContentView("extract")
    feedbin.formatEntryContent(id, false, false)
    feedbin.entryTime()
  }

  async toggleSticky(feedId) {
    try {
      const response = await request(this.feedUrl(this.stickyUrlValue, feedId), { method: "POST" })
      // No content: the user has no subscription to this feed.
      if (response.status === 204) return
      const { view_inline } = await response.json()
      window.feedbin.data.readability_settings[feedId] = view_inline
    } catch {}
  }

  extractSlot(id) {
    return window.$(`[data-entry-id=${id}] [data-content-option=extract]`)
  }

  async delete() {
    const id = this.entryIdValue
    const feedId = this.feedIdValue
    if (!id || !this.pagesValue) return
    if (!window.confirm("Are you sure you want to delete this page?")) return

    try {
      await request(this.entryUrl(this.deleteUrlValue, id), { method: "DELETE" })
    } catch {
      return
    }

    const feedbin = window.feedbin
    window.$(`[data-behavior~=entries_target] [data-entry-id=${id}]`).remove()
    feedbin.Counts.get().removeEntry(id, feedId, "unread")
    feedbin.Counts.get().removeEntry(id, feedId, "starred")
    feedbin.applyCounts(true)

    // Another entry may have opened while the request ran.
    if (this.entryIdValue === id) {
      feedbin.clearEntry()
      feedbin.fullScreen(false)
    }
  }

  // The old toolbar left the DOM with its entry. This one stays, so take out
  // everything that names the entry: the share links and the copy-link field
  // would still act on it from the keyboard. The entry controls hide while
  // entryId is 0.
  clear() {
    this.entryIdValue = 0
    this.feedIdValue = 0
    this.starredValue = false
    this.readValue = false
    this.extractValue = false
    this.loadingValue = false
    this.pagesValue = false
    this.subscribedValue = false
    this.headerTargets.forEach((header) => header.replaceChildren())
    this.feedLinkTarget.removeAttribute("href")
    this.sourceLinkTarget.value = ""
    this.element.querySelectorAll("[data-behavior~=share_options]").forEach((list) => list.replaceChildren())
    this.closeDropdowns()
  }

  // The old toolbar left the DOM on each entry, which closed its share menu.
  closeDropdowns() {
    this.element.querySelectorAll(".dropdown-wrap.open").forEach((dropdown) => {
      dropdown.classList.remove("open")
    })
  }

  // A new element each time: jQuery caches data-feed-id the first time
  // feedbin.applyUserTitles reads it, so a reused element would answer a
  // rename with the feed of an earlier entry.
  titleElement(data) {
    const title = document.createElement("span")
    title.className = "entry-feed-title"
    if (data.pages) {
      title.textContent = data.header_title
    } else {
      title.dataset.behavior = "user_title"
      title.dataset.feedId = data.feed_id
      title.textContent = userTitle(data.feed_id, data.header_title)
    }
    return title
  }

  entryUrl(template, id) {
    return template.replace("ENTRY_ID", id)
  }

  feedUrl(template, feedId) {
    return template.replace("FEED_ID", feedId)
  }
}
