import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["moveForm", "bookshelfInput", "tab", "dropzone", "dropHint"]
  static values = { selectedBookshelfId: Number }

  connect() {
    this.hoverDelay = 500
  }

  dragstart(event) {
    this.moveUrl = event.params.moveUrl
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.moveUrl)
  }

  dragend() {
    this.resetDragState()
    this.moveUrl = null
  }

  dragoverTab(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(event.currentTarget)
    this.scheduleArmTarget(event.currentTarget, event.params.bookshelfId, event.params.bookshelfName)
  }

  dragleaveTab(event) {
    this.clearArmTimer()
    this.unhighlight(event.currentTarget)
  }

  dropOnTab(event) {
    event.preventDefault()
    this.moveTo(event.params.bookshelfId)
    this.resetDragState()
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
    this.moveTo(this.armedBookshelfId || this.selectedBookshelfIdValue)
    this.resetDragState()
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

  scheduleArmTarget(tab, bookshelfId, bookshelfName) {
    const targetBookshelfId = Number(bookshelfId)
    if (!targetBookshelfId || targetBookshelfId === this.selectedBookshelfIdValue) return
    if (targetBookshelfId === this.armedBookshelfId) return
    if (targetBookshelfId === this.pendingBookshelfId) return

    this.clearArmTimer()
    this.clearArmedTarget()
    this.pendingBookshelfId = targetBookshelfId
    this.armTimer = window.setTimeout(() => {
      this.armedBookshelfId = targetBookshelfId
      this.armedBookshelfName = bookshelfName
      this.pendingBookshelfId = null
      this.highlight(tab)
      this.showDropHint()
    }, this.hoverDelay)
  }

  showDropHint() {
    if (!this.hasDropHintTarget || !this.armedBookshelfName) return

    this.dropHintTarget.textContent = `아래 책장 영역에 놓으면 '${this.armedBookshelfName}'으로 이동합니다.`
    this.dropHintTarget.classList.remove("hidden")
    if (this.hasDropzoneTarget) this.highlight(this.dropzoneTarget)
  }

  clearArmTimer() {
    if (!this.armTimer) return

    window.clearTimeout(this.armTimer)
    this.armTimer = null
    this.pendingBookshelfId = null
  }

  clearArmedTarget() {
    this.armedBookshelfId = null
    this.armedBookshelfName = null
    if (this.hasDropHintTarget) {
      this.dropHintTarget.textContent = ""
      this.dropHintTarget.classList.add("hidden")
    }
  }

  resetDragState() {
    this.clearArmTimer()
    this.clearArmedTarget()
    this.clearHighlights()
  }
}
