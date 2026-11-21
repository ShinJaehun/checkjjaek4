import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "createPanel", "editPanel", "closeButton"]

  openCreate(event) {
    this.open("create", event.currentTarget)
  }

  openEdit(event) {
    this.open("edit", event.currentTarget)
  }

  close() {
    if (!this.hasModalTarget || this.modalTarget.classList.contains("hidden")) return

    this.modalTarget.classList.add("hidden")
    this.opener?.focus()
    this.opener = null
  }

  closeOnBackdrop(event) {
    if (event.target !== this.modalTarget) return

    this.close()
  }

  open(mode, opener) {
    if (!this.hasModalTarget) return

    if (this.modalTarget.classList.contains("hidden")) this.opener = opener
    this.showPanel(mode)
    this.modalTarget.classList.remove("hidden")
    this.closeButtonTarget.focus()
  }

  showPanel(mode) {
    if (this.hasCreatePanelTarget) this.createPanelTarget.classList.toggle("hidden", mode !== "create")
    if (this.hasEditPanelTarget) this.editPanelTarget.classList.toggle("hidden", mode !== "edit")
  }
}
