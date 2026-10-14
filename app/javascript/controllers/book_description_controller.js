import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["text", "toggle", "expand", "collapse"]

  connect() {
    this.observer = new ResizeObserver(() => {
      if (this.toggleTarget.getAttribute("aria-expanded") === "false") {
        this.toggleTarget.hidden = this.textTarget.scrollHeight <= this.textTarget.clientHeight
      }
    })
    this.observer.observe(this.textTarget)
  }

  disconnect() {
    this.observer.disconnect()
  }

  toggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") !== "true"
    this.textTarget.classList.toggle("line-clamp-4", !expanded)
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.expandTarget.hidden = expanded
    this.collapseTarget.hidden = !expanded
  }
}
