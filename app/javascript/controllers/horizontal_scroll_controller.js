import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "selected"]

  connect() {
    requestAnimationFrame(() => this.scrollSelectedIntoView())
  }

  scrollLeft() {
    this.scrollBy(-280)
  }

  scrollRight() {
    this.scrollBy(280)
  }

  scrollBy(left) {
    if (!this.hasScrollerTarget) return

    this.scrollerTarget.scrollBy({ left, behavior: "smooth" })
  }

  scrollSelectedIntoView() {
    if (!this.hasScrollerTarget || !this.hasSelectedTarget) return

    const scroller = this.scrollerTarget
    const selected = this.selectedTarget
    const left = selected.offsetLeft - (scroller.clientWidth - selected.clientWidth) / 2

    scroller.scrollTo({ left: Math.max(0, left), behavior: "auto" })
  }
}
