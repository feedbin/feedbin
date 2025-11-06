import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="upload"
export default class extends Controller {
  static targets = ["dropzone", "fileInput", "form", "filenameField", "xmlField", "errorMessage"]
  static values = {
    dragging: Boolean,
    dropped: Boolean,
    error: Boolean,
  }

  connect() {
  }

  disconnect() {
  }

  dragStart(event) {
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = "copy"
    this.draggingValue = true
  }

  dragLeave(event) {
    event.preventDefault()
    event.stopPropagation()

    // Only remove the highlight if we're leaving the dropzone itself
    // not just moving between child elements
    if (event.target === this.dropzoneTarget) {
      this.draggingValue = false
    }
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()

    this.draggingValue = false

    const files = event.dataTransfer.files
    if (files && files.length > 0) {
      this.handleFiles(files[0])
    }
  }

  chooseFile(event) {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  fileSelected(event) {
    const files = event.target.files
    if (files.length > 0) {
      this.handleFiles(files[0])
    }
  }

  error(message) {
    this.errorValue = true
    this.errorMessageTarget.textContent = message
    setTimeout(() => {
      this.errorValue = false
    }, 2500)
  }

  handleFiles(file) {
    const maxSize = 500 * 1024
    if (file.size > maxSize) {
      this.error("File is too large. Maximum size is 500KB.")
      return
    }

    const reader = new FileReader()
    reader.onload = (event) => {
      const text = event.target.result

      if (!text.trimStart().startsWith("<?xml")) {
        this.error("Invalid file format. File must be XML/OPML.")
        return
      }

      this.filenameFieldTarget.value = file.name
      this.xmlFieldTarget.value = text
      window.$(this.formTarget).submit()
    }

    reader.onerror = (event) => {
      this.error("Error reading file. Please try again.")
      this.droppedValue = false
    }

    const fileSlice = file.slice(0, maxSize)
    reader.readAsText(fileSlice)
  }

}
