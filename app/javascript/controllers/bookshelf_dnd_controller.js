import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["moveForm", "bookshelfInput", "tab", "dropzone", "dropHint", "previewPanel"]
  static values = { selectedBookshelfId: Number }

  connect() {
    this.hoverDelay = 500
  }

  dragstart(event) {
    if (event.target.closest("[data-bookshelf-entries-sort-handle]")) return

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
    this.scheduleArmTarget(event.currentTarget, event.params.bookshelfId, event.params.bookshelfName, event.params.previewUrl)
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

  dragoverPreview(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(this.previewPanelTarget)
  }

  dragleavePreview() {
    this.unhighlight(this.previewPanelTarget)
  }

  dropOnPreview(event) {
    event.preventDefault()
    this.moveTo(this.armedBookshelfId)
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
    if (this.hasPreviewPanelTarget) this.unhighlight(this.previewPanelTarget)
  }

  scheduleArmTarget(tab, bookshelfId, bookshelfName, previewUrl) {
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
      this.fetchPreview(previewUrl, targetBookshelfId)
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
    this.clearPreview()
  }

  resetDragState() {
    this.clearArmTimer()
    this.clearArmedTarget()
    this.clearHighlights()
  }

  async fetchPreview(previewUrl, bookshelfId) {
    if (!this.hasPreviewPanelTarget || !previewUrl) return

    try {
      const response = await fetch(previewUrl, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
      if (!response.ok || this.armedBookshelfId !== bookshelfId) return

      this.previewPanelTarget.innerHTML = await response.text()
      this.previewPanelTarget.classList.remove("hidden")
    } catch (_error) {
      this.clearPreview()
    }
  }

  clearPreview() {
    if (!this.hasPreviewPanelTarget) return

    this.previewPanelTarget.innerHTML = ""
    this.previewPanelTarget.classList.add("hidden")
  }
}
