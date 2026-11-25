import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "menuTrigger", "modal", "createPanel", "editPanel", "closeButton"]

  openCreate() {
    this.open("create")
  }

  openEdit() {
    this.open("edit")
  }

  close() {
    if (!this.hasModalTarget || this.modalTarget.classList.contains("hidden")) return

    this.modalTarget.classList.add("hidden")
    this.menuTriggerTarget.focus()
  }

  closeMenu() {
    if (!this.menuTarget.open) return

    this.menuTarget.open = false
    this.menuTriggerTarget.focus()
  }

  closeMenuOnOutsideClick(event) {
    if (!this.menuTarget.contains(event.target)) this.menuTarget.open = false
  }

  closeOnBackdrop(event) {
    if (event.target !== this.modalTarget) return

    this.close()
  }

  open(mode) {
    if (!this.hasModalTarget) return

    this.menuTarget.open = false
    this.showPanel(mode)
    this.modalTarget.classList.remove("hidden")
    this.closeButtonTarget.focus()
  }

  showPanel(mode) {
    if (this.hasCreatePanelTarget) this.createPanelTarget.classList.toggle("hidden", mode !== "create")
    if (this.hasEditPanelTarget) this.editPanelTarget.classList.toggle("hidden", mode !== "edit")
  }
}
