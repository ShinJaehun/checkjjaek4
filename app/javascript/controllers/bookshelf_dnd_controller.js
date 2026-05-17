import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["moveForm", "bookshelfInput", "tab", "dropzone", "panel", "previewPanel"]
  static values = { selectedBookshelfId: Number }

  connect() {
    this.hoverDelay = 500
  }

  dragstart(event) {
    this.moveUrl = null
    const dragPreviewSource = event.target.closest("[data-bookshelf-dnd-drag-preview]")
    if (!dragPreviewSource && event.currentTarget.hasAttribute("data-bookshelf-entries-sort-handle")) return
    if (!dragPreviewSource && event.target.closest("a, button, input, select, textarea, summary, details, form")) return

    this.moveUrl = event.params.moveUrl
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.moveUrl)
    this.setDragPreview(event)
  }

  dragend() {
    this.resetDragState()
    this.clearDragPreview()
    this.moveUrl = null
  }

  dragoverTab(event) {
    if (!this.hasActiveMove()) return

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
    if (!this.hasActiveMove()) return

    event.preventDefault()
    this.moveTo(event.params.bookshelfId)
    this.resetDragState()
  }

  dragoverSelected(event) {
    if (!this.hasActiveMove()) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(this.dropzoneTarget)
  }

  dragleaveSelected() {
    this.unhighlight(this.dropzoneTarget)
  }

  dropOnSelected(event) {
    if (!this.hasActiveMove()) return

    event.preventDefault()
    this.moveTo(this.armedBookshelfId || this.selectedBookshelfIdValue)
    this.resetDragState()
  }

  dragoverPreview(event) {
    if (!this.hasActiveMove()) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.highlight(this.previewPanelTarget)
  }

  dragleavePreview() {
    this.unhighlight(this.previewPanelTarget)
  }

  dropOnPreview(event) {
    if (!this.hasActiveMove()) return

    event.preventDefault()
    this.moveTo(this.armedBookshelfId)
    this.resetDragState()
  }

  hasActiveMove() {
    return !!this.moveUrl
  }

  moveTo(bookshelfId) {
    const targetBookshelfId = Number(bookshelfId)
    if (!this.moveUrl || !targetBookshelfId) return
    if (targetBookshelfId === this.selectedBookshelfIdValue) return

    document.documentElement.dataset.bookshelfDndExternalMove = "true"
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
      this.fetchPreview(previewUrl, targetBookshelfId)
    }, this.hoverDelay)
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
      this.syncPreviewOverlayHeight()
    } catch (_error) {
      this.clearPreview()
    }
  }

  syncPreviewOverlayHeight() {
    if (!this.hasPreviewPanelTarget || !this.hasPanelTarget) return

    const minHeight = Math.max(this.panelTarget.offsetHeight, 384)
    this.previewPanelTarget.style.minHeight = `${minHeight}px`
  }

  clearPreview() {
    if (!this.hasPreviewPanelTarget) return

    this.previewPanelTarget.innerHTML = ""
    this.previewPanelTarget.style.minHeight = ""
    this.previewPanelTarget.classList.add("hidden")
  }

  setDragPreview(event) {
    const previewSource = event.currentTarget.querySelector("[data-bookshelf-dnd-drag-preview]")
    const image = previewSource?.querySelector("img")

    this.dragPreview = image?.complete ? image.cloneNode(true) : this.placeholderDragPreview(previewSource)
    this.dragPreview.classList.add("pointer-events-none")
    this.dragPreview.style.position = "fixed"
    this.dragPreview.style.top = "-1000px"
    this.dragPreview.style.left = "-1000px"
    this.dragPreview.style.width = "56px"
    this.dragPreview.style.height = "80px"
    this.dragPreview.style.objectFit = "contain"
    document.body.appendChild(this.dragPreview)

    event.dataTransfer.setDragImage(this.dragPreview, 28, 40)
  }

  placeholderDragPreview(previewSource) {
    const placeholder = previewSource?.querySelector("div")?.cloneNode(true) || document.createElement("div")
    placeholder.textContent = placeholder.textContent.trim() || "표지 없음"
    placeholder.className = "flex items-center justify-center rounded-sm border border-stone-200 bg-stone-50 px-2 text-center text-xs font-medium text-stone-400"
    return placeholder
  }

  clearDragPreview() {
    if (!this.dragPreview) return

    this.dragPreview.remove()
    this.dragPreview = null
  }
}
