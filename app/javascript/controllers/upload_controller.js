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

    console.log("event.dataTransfer", event.dataTransfer.items);

    window.Afiles = event.dataTransfer.items
    window.Aitems = event.dataTransfer.items

    const files = event.dataTransfer.items
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

  handleFiles(items) {
    this.droppedValue = true
    // this.fileInputTarget.files = files
    const files = [];
    for (const item of items) {
      if (item.kind === 'file') {
        const file = item.getAsFile();
        if (file) files.push(file);
      }
    }

    if (files.length > 0) {
      // Use DataTransfer to create a FileList
      const dt = new DataTransfer();
      files.forEach((file) => dt.items.add(file));

      // Assign to hidden input
      this.fileInputTarget.files = dt.files;

      console.log(this.fileInputTarget);

      // (optional) show a preview / confirmation
      // dropzone.textContent = `Attached: ${files.map(f => f.name).join(', ')}`;
    }
    window.$(this.formTarget).submit()
  }

}
