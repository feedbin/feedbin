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
  // Its entry-toolbar:show event then had no listener, so show that entry now.
  connect() {
    const feedbin = window.feedbin
    const entry = feedbin.selectedEntry && feedbin.entries[feedbin.selectedEntry.id]
    if (entry?.toolbar && !this.entryIdValue) {
      this.show({ detail: entry.toolbar })
    }
  }

  // detail is null when no entry is open, or when the entry came from a
  // server without toolbar data. Then every action does nothing.
  show(event) {
    const data = event.detail
    if (!data) {
      this.entryIdValue = 0
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

    // The old toolbar left the DOM on each entry, which closed its share menu.
    this.element.querySelectorAll(".dropdown-wrap.open").forEach((dropdown) => {
      dropdown.classList.remove("open")
    })

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

  toggleExtract() {
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
