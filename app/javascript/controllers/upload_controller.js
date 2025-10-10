import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="upload"
export default class extends Controller {
  static targets = ["dropzone", "fileInput"]
  static values = {
    hover: Boolean
  }

  connect() {
  }

  disconnect() {
  }

  dragStart(event) {
    console.log("dragStart", event);
  }

  dragOver(event) {
    console.log("dragOver", event);
    event.preventDefault()
    event.stopPropagation()
    this.dropzoneTarget.classList.add("border-blue-500")
    this.dropzoneTarget.classList.remove("border-200")
  }

  dragLeave(event) {
    event.preventDefault()
    event.stopPropagation()

    // Only remove the highlight if we're leaving the dropzone itself
    // not just moving between child elements
    if (event.target === this.dropzoneTarget) {
      this.dropzoneTarget.classList.remove("border-blue-500")
      this.dropzoneTarget.classList.add("border-200")
    }
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()

    this.dropzoneTarget.classList.remove("border-blue-500")
    this.dropzoneTarget.classList.add("border-200")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.handleFiles(files)
    }
  }

  chooseFile(event) {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  fileSelected(event) {
    console.log("selected", event);
    const files = event.target.files
    if (files.length > 0) {
      this.handleFiles(files)
    }
  }

  handleFiles(files) {
    // Handle the uploaded file(s) here
    // For OPML import, typically we'd send this to the server
    console.log("Files to upload:", files)

    // You can dispatch a custom event or submit a form
    // this.dispatch("filesSelected", { detail: { files: files } })

    // Or submit to server:
    const formData = new FormData()
    formData.append("file", files[0])

    // Example: POST to server
    // fetch('/import/opml', {
    //   method: 'POST',
    //   body: formData
    // })
  }

}
