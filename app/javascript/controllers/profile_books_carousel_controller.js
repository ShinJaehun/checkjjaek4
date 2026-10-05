import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "previous", "next", "position"]

  connect() {
    this.showPage(0)
  }

  previous() {
    this.showPage(this.index - 1)
  }

  next() {
    this.showPage(this.index + 1)
  }

  showPage(index) {
    if (index < 0 || index >= this.pageTargets.length) return

    this.index = index
    this.pageTargets.forEach((page, pageIndex) => {
      page.hidden = pageIndex !== index
      page.style.display = page.hidden ? "none" : ""
    })

    if (this.hasPreviousTarget) this.previousTarget.disabled = index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = index === this.pageTargets.length - 1
    if (this.hasPositionTarget) this.positionTarget.textContent = `${index + 1} / ${this.pageTargets.length}`
  }
}
