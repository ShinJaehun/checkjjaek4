import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thumbnail", "dialog", "image", "counter", "previous", "next", "error"]

  disconnect() { this.close() }

  open(event) {
    this.opener = event.currentTarget
    this.index = this.thumbnailTargets.indexOf(this.opener)
    this.dialogTarget.showModal()
    this.show()
  }

  close(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget || !this.dialogTarget.open) return
    this.dialogTarget.close()
    this.imageTarget.removeAttribute("src")
    this.opener?.focus({ preventScroll: true })
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  show() {
    this.errorTarget.hidden = true
    this.imageTarget.hidden = false
    this.imageTarget.src = this.thumbnailTargets[this.index].dataset.galleryUrl
    this.counterTarget.textContent = `${this.index + 1} / ${this.thumbnailTargets.length}`
    this.previousTarget.disabled = this.index === 0
    this.nextTarget.disabled = this.index === this.thumbnailTargets.length - 1
  }

  previous() {
    if (this.index > 0) { this.index--; this.show() }
  }

  next() {
    if (this.index < this.thumbnailTargets.length - 1) { this.index++; this.show() }
  }

  keydown(event) {
    if (!this.dialogTarget.open) return
    if (event.key === "Escape") this.close(event)
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
  }

  touchStart(event) {
    if (event.pointerType === "touch") this.touch = { x: event.clientX, y: event.clientY }
  }

  touchEnd(event) {
    if (!this.touch || event.pointerType !== "touch") return
    const dx = event.clientX - this.touch.x
    const dy = event.clientY - this.touch.y
    this.touch = null
    if (Math.abs(dx) < 50 || Math.abs(dx) < Math.abs(dy)) return
    if (dx > 0) this.previous()
    else this.next()
  }

  imageError() {
    this.imageTarget.hidden = true
    this.errorTarget.hidden = false
  }

  imageLoaded() { this.errorTarget.hidden = true }
  prevent(event) { event.preventDefault() }
}
