import { Controller } from "@hotwired/stimulus"

const allowedTypes = ["image/jpeg", "image/png", "image/webp"]

export default class extends Controller {
  static targets = ["input", "image", "preview", "remove", "removeButton", "pending", "error"]
  static values = { savedSource: String, maxSize: Number, removeLabel: String, cancelLabel: String }

  connect() {
    this.previewUrl = null
    this.render()
  }

  disconnect() {
    this.releasePreview()
  }

  change() {
    const file = this.inputTarget.files[0]
    this.releasePreview()
    this.removeTarget.value = "0"
    this.errorTarget.hidden = true

    if (file) {
      if (!allowedTypes.includes(file.type) || !file.size || file.size > this.maxSizeValue) {
        this.inputTarget.value = ""
        this.errorTarget.hidden = false
      } else {
        this.previewUrl = URL.createObjectURL(file)
      }
    }
    this.render()
  }

  remove() {
    if (this.previewUrl) {
      // Cancelling a new selection never marks the saved image for deletion.
      this.inputTarget.value = ""
      this.releasePreview()
    } else {
      this.removeTarget.value = "1"
    }
    this.errorTarget.hidden = true
    this.render()
    this.inputTarget.focus()
  }

  restore() {
    this.removeTarget.value = "0"
    this.render()
    this.inputTarget.focus()
  }

  imageError() {
    if (!this.previewUrl) return

    this.inputTarget.value = ""
    this.releasePreview()
    this.render()
    this.errorTarget.hidden = false
  }

  reset() {
    this.inputTarget.value = ""
    this.removeTarget.value = "0"
    this.releasePreview()
    this.errorTarget.hidden = true
    this.render()
  }

  render() {
    const removed = this.removeTarget.value === "1"
    const source = this.previewUrl || (removed ? "" : this.savedSourceValue)
    this.previewTarget.hidden = !source
    if (source) this.imageTarget.src = source
    else this.imageTarget.removeAttribute("src")
    this.removeButtonTarget.setAttribute("aria-label", this.previewUrl ? this.cancelLabelValue : this.removeLabelValue)
    this.pendingTarget.hidden = !removed
  }

  releasePreview() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
