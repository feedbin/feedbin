import { Controller } from "@hotwired/stimulus"
import { hydrate, userTitle } from "helpers"

// Connects to data-controller="search-token"
export default class extends Controller {
  static targets = [
    "query",
    "queryExtra",
    "focusable",
    "preview",
    "previewSource",
    "results",
    "resultTemplate",
    "headerTemplate",
    "tagIconTemplate",
    "tokenText",
    "tokenIcon",
  ]

  static values = {
    tokenVisible: Boolean,
    autocompleteVisible: Boolean,
  }

  static outlets = ["sourceable"]

  initialize() {
    this.sourceableTargetCount = 0
  }

  sourceableOutletConnected() {
    this.buildJumpable()
  }

  search() {
    this.autocompleteVisibleValue = false
    this.skipAfterFocus = true
  }

  hideSearch() {
    this.queryTarget.value = ""
    this.autocompleteVisibleValue = false
    this.focusableTargets.forEach((element) => element.blur())
  }

  deleteToken(focusQuery = true) {
    this.tokenVisibleValue = false
    this.tokenTextTarget.innerHTML = ""
    this.tokenIconTarget.innerHTML = ""
    this.queryExtraTarget.value = ""
    this.updatePreview()
    if (focusQuery) {
      this.queryTarget.focus()
    }
  }

  clickOff(event) {
    if (event && this.element.contains(event.target)) {
      return
    }
    this.autocompleteVisibleValue = false
  }

  tokenSelected(event) {
    let index = event.params.index
    if (index === "") {
      let form = this.queryTarget.closest("form")
      this.skipAfterFocus = true
      window.$(form).submit()
      this.queryTarget.focus()
    } else {
      let item = this.jumpableItems[index]
      this.fillToken(item)
      this.queryTarget.focus()
    }
    this.autocompleteVisibleValue = false
    this.resultsTarget.innerHTML = ""
    event.preventDefault()
  }

  fillToken(item) {
    this.tokenTextTarget.textContent = item.title
    this.tokenIconTarget.innerHTML = ""
    if ("icon" in item) {
      this.tokenIconTarget.append(item.icon.cloneNode(true))
    }
    this.tokenVisibleValue = true
    this.queryTarget.value = ""
    this.queryExtraTarget.value = item.queryFilter
  }

  updateToken(event) {
    const detail = event.detail
    if (detail.jumpable) {
      this.deleteToken(false)
      let item = this.buildItem(detail, event.target)
      setTimeout(() => {
        this.fillToken(item)
      }, 150)
    } else {
      this.deleteToken(false)
    }
  }

  buildAutocomplete() {
    if (this.tokenVisibleValue) {
      return
    }

    const resultTemplate = this.resultTemplateTarget.content
    const headerTemplate = this.headerTemplateTarget.content

    let items = this.jumpableItems.filter((item) => {
      if (item.type === "feed") {
        item["title"] = userTitle(item.id, item.title)
      }
      const titleFolded = item.title.foldToASCII()
      const queryFolded = this.queryTarget.value.foldToASCII()
      item.score = titleFolded.score(queryFolded)
      return item.score > 0
    })
    items = window._.sortBy(items, function (item) {
      return -item.score
    })
    items = window._.groupBy(items, function (item) {
      return item.section
    })

    let elements = []
    const sections = Object.keys(items)
    sections.sort()
    sections.forEach((section) => {
      let header = headerTemplate.cloneNode(true)
      let element = hydrate(header, [
        {
          type: "text",
          name: "text",
          value: section,
        },
      ])
      elements.push(element)
      items[section].slice(0, 5).forEach((item) => {
        let element = resultTemplate.cloneNode(true)
        let updates = [
          {
            type: "text",
            name: "text",
            value: item.title,
          },
          {
            type: "attribute",
            name: `data-${this.identifier}-index-param`,
            value: item.index,
          },
        ]

        if ("icon" in item) {
          updates.push({
            type: "html",
            name: "icon",
            value: item.icon.cloneNode(true),
          })
        }

        elements.push(hydrate(element, updates))
      })
    })

    this.resultsTarget.innerHTML = ""
    this.resultsTarget.append(...elements)
  }

  updatePreview() {
    this.previewTarget.textContent = this.queryTarget.value

    let sourceText = ""
    if (this.tokenTextTarget.textContent != "") {
      sourceText = this.tokenTextTarget.textContent
    }
    this.previewSourceTarget.textContent = sourceText
  }

  keyup() {
    if (!this.skipAfterFocus && this.queryTarget.value.length > 0) {
      this.autocompleteVisibleValue = true
    } else {
      this.autocompleteVisibleValue = false
    }

    this.skipAfterFocus = false
    this.updatePreview()
    this.buildAutocomplete()
  }

  checkToken(event) {
    this.updatePreview()
    if (event.key !== "Backspace") {
      return
    }

    // command + delete
    if (event.metaKey) {
      this.deleteToken()
    } else if (this.queryTarget.value.length === 0) {
      this.deleteToken()
    }
  }

  focused() {
    this.currentFocusable = this.focusableTargets[0]
    if (this.tokenVisibleValue) {
      return
    }
    if (this.queryTarget.value.length > 0) {
      this.autocompleteVisibleValue = true
    }
  }

  navigate(event) {
    const count = this.focusableTargets.length
    if (!this.autocompleteVisibleValue || count == 0) {
      return
    }

    const currentIndex = this.focusableTargets.indexOf(this.currentFocusable)

    let nextIndex = (currentIndex + 1) % count
    if (event.key === "ArrowUp") {
      nextIndex = (currentIndex + count - 1) % count
    }

    this.currentFocusable = this.focusableTargets[nextIndex]
    this.currentFocusable.focus()

    if ("setSelectionRange" in this.currentFocusable) {
      this.currentFocusable.setSelectionRange(
        this.currentFocusable.value.length,
        this.currentFocusable.value.length
      )
    }

    event.preventDefault()
    event.stopPropagation()
  }

  buildItem(data, element) {
    const tagIconTemplate = this.tagIconTemplateTarget.content
    const icon =
      element.querySelector(".favicon-wrap") || tagIconTemplate.cloneNode(true)
    data["icon"] = icon.cloneNode(true)
    data["element"] = element
    data["queryFilter"] = `${data.type}_id:${data.id}`

    return data
  }

  buildJumpable() {
    let sourceableTargets = this.sourceableOutlet.sourceTargets
    if (this.sourceableTargetCount === sourceableTargets.length) {
      return
    }
    this.sourceableTargetCount = sourceableTargets.length

    let uniqueSources = new Set()
    this.jumpableItems = sourceableTargets
      .reduce((filtered, element) => {
        let data = JSON.parse(element.dataset.sourceablePayloadParam)
        let item = this.buildItem(data, element)
        if (item.jumpable && !uniqueSources.has(item.queryFilter)) {
          filtered.push(item)
          uniqueSources.add(item.queryFilter)
        }
        return filtered
      }, [])
      .map((item, index) => {
        item.index = index
        return item
      })
  }
}
