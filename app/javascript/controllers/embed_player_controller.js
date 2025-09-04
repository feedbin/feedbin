import { Controller } from "@hotwired/stimulus"
import { html } from "helpers"

export default class extends Controller {
  static targets = [
    "chapterButton",
    "playButton",
    "videoContainer",
    "iframe",
    "iframeTemplate",
  ]
  static values = {
    sourceUrl: String,
    width: Number,
    height: Number,
    loaded: Boolean,
    chaptersOpen: Boolean,
    youtube: Boolean,
    hasImage: Boolean,
  }
  static outlets = ["expandable"]

  connect() {
    this.player = null
    this.currentChapterIndex = null
    this.checkInterval = null
    this.isPlaying = false
    this.seekOnLoad = 0

    // Listen for messages from YouTube iframe
    this.boundMessageHandler = this.handleMessage.bind(this)
    window.addEventListener("message", this.boundMessageHandler)
  }

  disconnect() {
    if (this.checkInterval) {
      clearInterval(this.checkInterval)
    }
    window.removeEventListener("message", this.boundMessageHandler)
  }

  showPlayer() {
    this.loadedValue = true

    if (!this.hasIframeTarget) {
      this.createIframe()
    }

    this.hasImageValue = true
    this.isPlaying = true
  }

  toggleChapters(event) {
    this.chaptersOpenValue = !this.chaptersOpenValue
    this.expandableOutlet.toggle()
  }

  selectChapter(event) {
    event.preventDefault()
    const button = event.currentTarget
    const seconds = parseInt(button.dataset.embedPlayerSecondsParam)
    const index = this.chapterButtonTargets.indexOf(button)

    this.updateActiveChapter(index)

    if (this.isPlaying && this.player) {
      this.seekToTime(seconds)
    } else {
      // If not playing, start playing at this chapter
      this.showPlayer()
      this.seekOnLoad = seconds
    }
  }

  swapIframe(event) {
    // when an image is present this functions like a normal link
    if (this.hasImageValue) {
      return
    }

    this.showPlayer()

    event.preventDefault()
  }

  createIframe() {
    const template = this.iframeTemplateTarget.content.cloneNode(true)
    const iframe = template.querySelector("iframe")
    iframe.onload = () => {
      this.startTimeTracking()
    }
    html(this.videoContainerTarget, template)
  }

  startTimeTracking() {
    if (!this.youtubeValue) return

    this.player = this.iframeTarget.contentWindow

    this.postMessage({
      event: "command",
      func: "addEventListener",
      args: ["onReady"],
    })

    this.checkInterval = setInterval(() => {
      this.postMessage({
        event: "listening",
      })
    }, 1000)

    this.seekToTime(this.seekOnLoad)
  }

  seekToTime(seconds) {
    this.postMessage({
      event: "command",
      func: "seekTo",
      args: [seconds, true],
    })
    this.postMessage({event: "command", func: "playVideo"})
  }

  postMessage(message) {
    if (this.player) {
      this.player.postMessage(JSON.stringify(message), "*")
    }
  }

  updateActiveChapter(newIndex) {
    this.currentChapterIndex = newIndex
    this.chapterButtonTargets.forEach((button, index) => {
      button.dataset.selected = (newIndex === index) ? "true" : "false"
    })
  }

  handleMessage(event) {
    const data = this.parseData(event)
    if (!data) return

    if (data.event === "infoDelivery" && data.info?.currentTime != null) {
      this.findCurrentChapter(data.info.currentTime)
    }
  }

  findCurrentChapter(currentTime) {
    // Walk backwards to find a matching chapter
    for (let index = this.chapterButtonTargets.length - 1; index >= 0; index--) {
      const buttonSeconds = Number(this.chapterButtonTargets[index].dataset.embedPlayerSecondsParam)
      if (currentTime >= buttonSeconds) {
        if (this.currentChapterIndex !== index) {
          this.updateActiveChapter(index)
        }
        break
      }
    }
  }

  parseData(event) {
    if (event.source !== this.player || !event.data) {
      return null
    }

    try {
      const data = JSON.parse(event.data)
      if (data.event) {
        return data
      }
    } catch (_) {

    }

    return null
  }
}
