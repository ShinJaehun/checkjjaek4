import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "selected", "previous", "next"]

  connect() {
    if (!this.hasScrollerTarget) return

    this.resizeObserver = new ResizeObserver(() => this.layout())
    this.resizeObserver.observe(this.scrollerTarget)
    this.mutationObserver = new MutationObserver(() => this.layout())
    this.mutationObserver.observe(this.scrollerTarget, { childList: true, subtree: true, characterData: true })
    this.animationFrame = requestAnimationFrame(() => this.layout())
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.mutationObserver?.disconnect()
    cancelAnimationFrame(this.animationFrame)
  }

  layout() {
    this.updateControls()
    this.scrollSelectedIntoView()
    this.updateControls()
  }

  updateControls() {
    if (!this.hasScrollerTarget) return

    const scroller = this.scrollerTarget
    // Compare with the full row so the buttons cannot cause overflow themselves.
    const overflowing = scroller.scrollWidth > this.element.clientWidth + 1

    this.previousTarget.classList.toggle("hidden", !overflowing)
    this.nextTarget.classList.toggle("hidden", !overflowing)
    this.previousTarget.disabled = !overflowing || scroller.scrollLeft <= 1
    this.nextTarget.disabled = !overflowing || scroller.scrollLeft + scroller.clientWidth >= scroller.scrollWidth - 1
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
