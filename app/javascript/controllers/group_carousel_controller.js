import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "card", "controls", "previous", "next", "position"]

  connect() {
    this.desktopQuery = window.matchMedia("(min-width: 1024px)")
    this.tabletQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => this.resize()
    this.desktopQuery.addEventListener("change", this.handleBreakpointChange)
    this.tabletQuery.addEventListener("change", this.handleBreakpointChange)
    this.index = 0
    this.pageSize = 3
    this.resize()
  }

  disconnect() {
    this.desktopQuery.removeEventListener("change", this.handleBreakpointChange)
    this.tabletQuery.removeEventListener("change", this.handleBreakpointChange)
  }

  resize() {
    const focusedIndex = this.cardTargets.findIndex(card => card.contains(document.activeElement))
    const firstCardIndex = focusedIndex >= 0 ? focusedIndex : this.index * this.pageSize
    this.pageSize = this.desktopQuery.matches ? 3 : this.tabletQuery.matches ? 2 : 1
    this.pageCount = Math.ceil(this.cardTargets.length / this.pageSize)
    this.showPage(Math.floor(firstCardIndex / this.pageSize))
  }

  previous() {
    this.showPage(this.index - 1)
  }

  next() {
    this.showPage(this.index + 1)
  }

  showPage(index) {
    if (index < 0 || index >= this.pageCount) return

    // A swipe can start on a link; keep focus out of the page being hidden.
    const start = index * this.pageSize
    const end = start + this.pageSize
    const focusedIndex = this.cardTargets.findIndex(card => card.contains(document.activeElement))
    if (focusedIndex >= 0 && (focusedIndex < start || focusedIndex >= end)) {
      this.viewportTarget.focus({ preventScroll: true })
    }
    if (this.pageCount === 1 && this.controlsTarget.contains(document.activeElement)) {
      this.viewportTarget.focus({ preventScroll: true })
    }

    this.index = index
    this.cardTargets.forEach((card, cardIndex) => {
      card.hidden = cardIndex < start || cardIndex >= end
    })
    this.controlsTarget.hidden = this.pageCount === 1
    this.previousTarget.disabled = index === 0
    this.nextTarget.disabled = index === this.pageCount - 1
    this.positionTarget.textContent = `${index + 1} / ${this.pageCount}`
  }

  navigate(event) {
    if (event.target !== this.viewportTarget || event.altKey || event.ctrlKey || event.metaKey) return

    switch (event.key) {
      case "ArrowLeft":
        this.previous()
        break
      case "ArrowRight":
        this.next()
        break
      case "Home":
        this.showPage(0)
        break
      case "End":
        this.showPage(this.pageCount - 1)
        break
      default:
        return
    }
    event.preventDefault()
  }

  touchStart(event) {
    this.touchOrigin = event.touches.length === 1 ? event.touches[0] : null
  }

  touchEnd(event) {
    const origin = this.touchOrigin
    this.touchOrigin = null
    if (!origin || event.touches.length || event.changedTouches.length !== 1) return

    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - origin.clientX
    const deltaY = touch.clientY - origin.clientY
    if (Math.abs(deltaX) < 50 || Math.abs(deltaX) <= Math.abs(deltaY)) return

    if (deltaX < 0) this.next()
    else this.previous()
  }

  touchCancel() {
    this.touchOrigin = null
  }
}
