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
    this.videoDuration = 0

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

  toggleChapters() {
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
    this.postMessage({ event: "command", func: "playVideo" })
  }

  postMessage(message) {
    if (this.player) {
      this.player.postMessage(JSON.stringify(message), "*")
    }
  }

  updateActiveChapter(newIndex) {
    this.currentChapterIndex = newIndex
    this.chapterButtonTargets.forEach((button, index) => {
      button.dataset.selected = newIndex === index ? "true" : "false"
    })
  }

  updateChapterCountdown(currentTime) {
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

    if (this.currentChapterIndex === null || !this.isPlaying) return

    const currentButton = this.chapterButtonTargets[this.currentChapterIndex]
    let nextChapterTime = this.videoDuration
    if (this.currentChapterIndex + 1 < this.chapterButtonTargets.length) {
      const nextButton = this.chapterButtonTargets[this.currentChapterIndex + 1]
      nextChapterTime = Number(nextButton.dataset.embedPlayerSecondsParam)
    }

    const seconds = Math.max(0, nextChapterTime - currentTime)
    const timeString = this.secondsToDuration(seconds)
    this.chapterButtonTargets.forEach((button, index) => {
      const duration = button.querySelector("[data-embed-player-duration]")
      if (index === this.currentChapterIndex) {
        duration.textContent = timeString
      } else {
        duration.textContent = button.dataset.embedPlayerDurationParam
      }
    })
  }

  handleMessage(event) {
    const data = this.parseData(event)
    if (!data) return

    if (data.event === "infoDelivery" && data.info?.currentTime != null) {
      this.updateChapterCountdown(data.info.currentTime)
    }

    if (data.event === "infoDelivery" && data.info?.duration != null) {
      this.videoDuration = data.info.duration
    }
  }

  secondsToDuration(total) {
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = Math.floor(total % 60)

    const paddedMinutes = minutes.toString().padStart(2, "0")
    const paddedSeconds = seconds.toString().padStart(2, "0")

    let duration
    if (hours > 0) {
      // Hours: 1:01:01
      duration = `${hours}:${paddedMinutes}:${paddedSeconds}`
    } else if (minutes === 0) {
      // Seconds: 0:01
      duration = `0:${paddedSeconds}`
    } else {
      // Minutes: 1:11
      duration = `${minutes}:${paddedSeconds}`
    }

    return duration
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
      // Ignore parsing errors
    }

    return null
  }
}
