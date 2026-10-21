import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]
  static values = { autoOpen: Boolean }

  connect() {
    if (this.autoOpenValue) this.open()
  }

  disconnect() {
    this.restore()
  }

  open(event) {
    if (!this.hasDialogTarget || this.dialogTarget.open) return

    this.opener = event?.currentTarget || this.element.querySelector("[aria-haspopup='dialog']")
    this.previousOverflow = document.body.style.overflow
    this.dialogTarget.showModal()
    document.body.style.overflow = "hidden"
  }

  close() {
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
    this.restore()
  }

  restore() {
    if (this.previousOverflow === undefined) return

    document.body.style.overflow = this.previousOverflow
    this.previousOverflow = undefined
    this.opener?.focus()
  }
}
