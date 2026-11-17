import { Controller } from "@hotwired/stimulus"

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"]

export default class extends Controller {
  static targets = ["image", "input", "status", "error", "removeControl", "removeButton"]
  static values = { maxSize: Number, saved: Boolean, removeLabel: String, cancelLabel: String }

  connect() {
    this.savedSource = this.imageTarget.getAttribute("src")
    this.previewUrl = null
    this.syncRemoveButton()
  }

  disconnect() {
    this.releasePreview()
  }

  change() {
    const file = this.inputTarget.files[0]
    this.clearPreview()
    this.errorTarget.classList.add("hidden")

    if (!file) return

    if (!ALLOWED_TYPES.includes(file.type) || file.size > this.maxSizeValue) {
      this.inputTarget.value = ""
      this.errorTarget.classList.remove("hidden")
      return
    }

    this.previewUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.previewUrl
    this.statusTarget.classList.remove("hidden")
    this.syncRemoveButton()
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.previewUrl) {
      this.reset()
      this.inputTarget.focus()
    } else if (this.savedValue) {
      this.removeControlTarget.requestSubmit()
    }
  }

  cancel() {
    this.reset()
  }

  imageError() {
    if (!this.previewUrl) return

    this.inputTarget.value = ""
    this.clearPreview()
    this.errorTarget.classList.remove("hidden")
  }

  reset() {
    this.inputTarget.value = ""
    this.clearPreview()
    this.errorTarget.classList.add("hidden")
  }

  clearPreview() {
    this.imageTarget.src = this.savedSource
    this.statusTarget.classList.add("hidden")
    this.releasePreview()
    this.syncRemoveButton()
  }

  syncRemoveButton() {
    this.removeControlTarget.hidden = !this.previewUrl && !this.savedValue
    this.removeButtonTarget.setAttribute("aria-label", this.previewUrl ? this.cancelLabelValue : this.removeLabelValue)
  }

  releasePreview() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
