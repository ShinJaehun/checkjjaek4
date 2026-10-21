import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "page", "previous", "next", "position"]

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

    // A swipe can start on a link; keep focus out of the page being hidden.
    const focusedPage = this.pageTargets.find(page => page.contains(document.activeElement))
    if (focusedPage && focusedPage !== this.pageTargets[index]) this.viewportTarget.focus({ preventScroll: true })

    this.index = index
    this.pageTargets.forEach((page, pageIndex) => {
      page.hidden = pageIndex !== index
    })
    this.previousTarget.disabled = index === 0
    this.nextTarget.disabled = index === this.pageTargets.length - 1
    this.positionTarget.textContent = `${index + 1} / ${this.pageTargets.length}`
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
        this.showPage(this.pageTargets.length - 1)
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
