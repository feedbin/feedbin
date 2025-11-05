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

    const files = event.dataTransfer.files
    if (files.length > 0) {
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

  async handleFiles(files) {
    this.droppedValue = true
    this.fileInputTarget.files = files
    window.$(this.formTarget).submit()
    // this.formTarget.submit()
    //
    // try {
    //   const response = await fetch(this.formTarget.action, {
    //     method: "POST",
    //     body: formData,
    //     headers: {
    //       "X-CSRF-Token": csrfToken,
    //       "Accept": "text/javascript"
    //     }
    //   })
    //
    //   if (response.ok) {
    //     const script = await response.text()
    //     eval(script)
    //   } else {
    //     console.error("Upload failed:", response.statusText)
    //   }
    // } catch (error) {
    //   console.error("Upload error:", error)
    // } finally {
    //   this.droppedValue = false
    // }
  }

}
