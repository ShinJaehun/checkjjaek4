import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["moveForm", "bookshelfInput", "tab", "dropzone"]
  static values = { selectedBookshelfId: Number }

  dragstart(event) {
    this.moveUrl = event.params.moveUrl
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.moveUrl)
  }

  dragend() {
    this.clearHighlights()
    this.moveUrl = null
  }

  dragoverTab(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(event.currentTarget)
  }

  dragleaveTab(event) {
    this.unhighlight(event.currentTarget)
  }

  dropOnTab(event) {
    event.preventDefault()
    this.moveTo(event.params.bookshelfId)
    this.clearHighlights()
  }

  dragoverSelected(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(this.dropzoneTarget)
  }

  dragleaveSelected() {
    this.unhighlight(this.dropzoneTarget)
  }

  dropOnSelected(event) {
    event.preventDefault()
    this.moveTo(this.selectedBookshelfIdValue)
    this.clearHighlights()
  }

  moveTo(bookshelfId) {
    const targetBookshelfId = Number(bookshelfId)
    if (!this.moveUrl || !targetBookshelfId) return
    if (targetBookshelfId === this.selectedBookshelfIdValue) return

    this.moveFormTarget.action = this.moveUrl
    this.bookshelfInputTarget.value = targetBookshelfId
    this.moveFormTarget.requestSubmit()
  }

  highlight(element) {
    this.clearHighlights()
    element.classList.add("outline", "outline-2", "outline-stone-400", "outline-offset-2")
  }

  unhighlight(element) {
    element.classList.remove("outline", "outline-2", "outline-stone-400", "outline-offset-2")
  }

  clearHighlights() {
    this.tabTargets.forEach((tab) => this.unhighlight(tab))
    if (this.hasDropzoneTarget) this.unhighlight(this.dropzoneTarget)
  }
}
