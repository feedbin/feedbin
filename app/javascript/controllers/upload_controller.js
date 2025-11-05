import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="upload"
export default class extends Controller {
  static targets = ["dropzone", "fileInput", "form"]
  static values = {
    dragging: Boolean,
    dropped: Boolean
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
    event.dataTransfer.dropEffect = "copy";
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

    const items = event.dataTransfer.items
    if (items && items.length > 0) {
      this.handleFiles(items)
      return
    }

    const files = event.dataTransfer.files
    if (files && files.length > 0) {
      this.handleFiles(files)
    }
  }

  fileSelected(event) {
    const files = event.target.files
    if (files.length > 0) {
      this.handleFiles(files)
    }
  }

  chooseFile(event) {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  handleFiles(items) {
    this.droppedValue = true

    const files = this.extractFiles(items)

    if (files.length > 0) {
      this.assignFiles(items, files)
      this.submitForm()
    }
  }

  extractFiles(items) {
    if (!items) return []

    const files = []

    Array.from(items).forEach((item) => {
      if (item instanceof File) {
        files.push(item)
        return
      }

      if (item && item.kind === "file" && typeof item.getAsFile === "function") {
        const file = item.getAsFile()
        if (file) files.push(file)
      }
    })

    return files
  }

  assignFiles(source, files) {
    if (!this.hasFileInputTarget) return

    if (typeof FileList !== "undefined" && source instanceof FileList) {
      this.fileInputTarget.files = source
      return
    }

    if (typeof DataTransfer === "undefined") return

    const dt = new DataTransfer()
    files.forEach((file) => dt.items.add(file))

    this.fileInputTarget.files = dt.files
  }

  submitForm() {
    console.log(this.formTarget);
    // window.$(this.formTarget).submit()
  }
}
