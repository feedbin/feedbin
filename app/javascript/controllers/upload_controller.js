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
    console.log("dragStart", event);
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = "copy";
    console.log("dragOver", event.dataTransfer.items);
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
    console.log(this.formTarget);
    const formData = new FormData()
    formData.append("file", files[0])
    this.formTarget.requestSubmit()
  }

}
