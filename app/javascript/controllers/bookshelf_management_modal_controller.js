import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "createPanel", "editPanel"]

  openCreate() {
    this.open("create")
  }

  openEdit() {
    this.open("edit")
  }

  close() {
    if (!this.hasModalTarget) return

    this.modalTarget.classList.add("hidden")
  }

  closeOnBackdrop(event) {
    if (event.target !== this.modalTarget) return

    this.close()
  }

  open(mode) {
    if (!this.hasModalTarget) return

    this.showPanel(mode)
    this.modalTarget.classList.remove("hidden")
  }

  showPanel(mode) {
    if (this.hasCreatePanelTarget) this.createPanelTarget.classList.toggle("hidden", mode !== "create")
    if (this.hasEditPanelTarget) this.editPanelTarget.classList.toggle("hidden", mode !== "edit")
  }
}
