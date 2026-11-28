import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.updatePositioning()
  }

  disconnect() {
    this.stopPositioning()
  }

  updatePositioning() {
    if (!this.element.open) {
      this.stopPositioning()
      return
    }

    this.positionPanel()
    window.addEventListener("resize", this.positionPanel)
    window.addEventListener("scroll", this.positionPanel, { passive: true })
  }

  stopPositioning() {
    window.removeEventListener("resize", this.positionPanel)
    window.removeEventListener("scroll", this.positionPanel)
  }

  positionPanel = () => {
    const panel = this.panelTarget
    const margin = 8
    const gap = 6
    const { clientWidth, clientHeight } = document.documentElement
    const { left, top, bottom } = this.element.getBoundingClientRect()
    panel.style.maxWidth = `${clientWidth - 2 * margin}px`

    const width = panel.getBoundingClientRect().width
    // Use the full content height even after the previous position limited the panel.
    const height = panel.scrollHeight + panel.offsetHeight - panel.clientHeight
    const below = clientHeight - bottom - gap - margin
    const above = top - gap - margin
    const openAbove = height > below && above > below
    const panelLeft = Math.max(margin, Math.min(left, clientWidth - width - margin))

    panel.style.left = `${panelLeft - left}px`
    panel.style.top = openAbove ? "auto" : `calc(100% + ${gap}px)`
    panel.style.bottom = openAbove ? `calc(100% + ${gap}px)` : "auto"
    panel.style.maxHeight = `${Math.max(0, openAbove ? above : below)}px`
  }

  closeFromKeyboard() {
    if (!this.element.open) return

    this.element.open = false
    this.element.querySelector("summary").focus()
  }

  closeFromOutside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.element.open = false
  }
}
