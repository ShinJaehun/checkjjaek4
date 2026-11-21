import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["dialog", "opener", "title", "editor", "attachmentError"]
  static values = { discardMessage: String, discardPath: String }

  connect() {
    if (this.hasDiscardPathValue) this.open()
  }

  open() {
    if (this.dialogTarget.open) return

    this.initialTitle = this.titleTarget.value
    this.initialBody = this.editorTarget.value
    this.attachmentErrorTarget.hidden = true
    this.dialogTarget.showModal()
  }

  close(event) {
    event.preventDefault()
    const changed = this.hasDiscardPathValue ||
      this.titleTarget.value !== this.initialTitle ||
      this.editorTarget.value !== this.initialBody
    if (changed && !window.confirm(this.discardMessageValue)) return

    this.dialogTarget.close()
    this.openerTarget.focus()

    if (this.hasDiscardPathValue) {
      Turbo.visit(this.discardPathValue, { action: "replace" })
    } else if (changed) {
      this.titleTarget.value = this.initialTitle
      this.editorTarget.value = this.initialBody
    }
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close(event)
  }

  rejectFile(event) {
    event.preventDefault()
    this.attachmentErrorTarget.hidden = false
  }

  rejectAttachment(event) {
    event.attachment.remove()
    this.attachmentErrorTarget.hidden = false
  }
}
