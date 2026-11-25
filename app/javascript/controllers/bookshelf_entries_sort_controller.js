import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["controls", "downButton", "list", "selectedStatus", "spacer", "upButton"]
  static values = {
    bookshelfId: Number,
    reorderUrl: String,
    errorMessage: String,
    moveUpLabel: String,
    moveDownLabel: String
  }

  connect() {
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.touchQuery = window.matchMedia("(pointer: coarse)")
    this.useSortable(this.hasControlsTarget && this.touchQuery.matches)
    this.syncControls()
  }

  disconnect() {
    if (this.dragStartOrder) Sortable.ghost?.remove()
    this.clearSelection()
    this.destroySortable()
    this.dragStartOrder = null
    this.holdingCover = false
    this.suppressClickUntil = 0
  }

  prepareInput(event) {
    if (!this.listTarget.contains(event.target) || Sortable.dragged) return

    const touch = event.type === "touchstart" || event.pointerType === "touch"
    if (!touch && event.sourceCapabilities?.firesTouchEvents) return
    if (event.type === "mousedown" && this.clickSuppressed()) return
    if (touch || event.type === "pointerdown") this.suppressClickUntil = 0
    if (this.saving) return

    // Choose on input, not on resize. A phone can be wider than the desktop breakpoint in landscape.
    const mobile = this.hasControlsTarget && touch && (this.touchInput || this.touchQuery.matches || !this.desktopQuery.matches)
    this.useSortable(mobile)
  }

  useSortable(mobile) {
    if (this.sortable && this.touchInput === mobile) return

    this.destroySortable()
    this.touchInput = mobile
    this.listTarget.toggleAttribute("data-touch-reorder", mobile)
    if (!mobile && !this.touchQuery.matches) this.clearSelection()

    const options = mobile ? {
      handle: "[data-bookshelf-cover]",
      filter: (event) => event.type !== "touchstart",
      group: { pull: false, put: false },
      delay: 350,
      touchStartThreshold: 5,
      fallbackTolerance: 4,
      // Touch events allow a swipe before the hold and cancel scrolling once dragging.
      supportPointer: false,
      forceFallback: true,
      fallbackOnBody: true,
      chosenClass: "bookshelf-reorder-held",
      ghostClass: "bookshelf-reorder-placeholder",
      onChoose: ({ item }) => {
        this.holdingCover = true
        this.selectEntry(item)
      },
      onUnchoose: () => {
        if (this.holdingCover) this.suppressClickUntil = performance.now() + 500
        this.holdingCover = false
        this.syncControls()
      }
    } : {
      handle: "[data-bookshelf-entries-sort-handle]",
      filter: (event, _item, sortable) => !this.desktopQuery.matches || !!sortable.closest(event.target,
        "a, button:not([data-bookshelf-cover]), input, select, textarea, summary, details, form, dialog")
    }

    this.sortable = Sortable.create(this.listTarget, {
      animation: 120,
      draggable: "[data-bookshelf-entry-id]",
      preventOnFilter: false,
      onStart: () => this.startDrag(),
      onEnd: (event) => this.endDrag(event),
      ...options
    })
  }

  destroySortable() {
    if (!this.sortable) return

    const coverImages = this.sortable.el.querySelectorAll("[data-bookshelf-cover] img")
    this.sortable.destroy()
    this.sortable = null
    // Sortable removes draggable attributes on destroy. Cover images must stay non-draggable.
    coverImages.forEach((image) => { image.draggable = false })
  }

  clickSuppressed() {
    return performance.now() < this.suppressClickUntil
  }

  handleCoverClick(event) {
    const pointerClick = event.detail || event.pointerType === "touch" || event.sourceCapabilities?.firesTouchEvents
    if (pointerClick && this.clickSuppressed()) {
      this.suppressClickUntil = 0
      event.stopImmediatePropagation()
      return
    }
    this.clearSelection()
  }

  selectWithKeyboard(event) {
    if (!this.hasControlsTarget || (!this.touchInput && !this.touchQuery.matches)) return

    event.preventDefault()
    if (this.saving || Sortable.dragged) return

    this.selectEntry(event.currentTarget.closest("[data-bookshelf-entry-id]"))
    this.controlsTarget.querySelector("button:not(:disabled)")?.focus({ preventScroll: true })
  }

  selectEntry(entry) {
    this.selectedEntry?.removeAttribute("data-reorder-selected")
    this.selectedEntry = entry
    this.selectedEntry?.setAttribute("data-reorder-selected", "")
    this.syncControls()
  }

  clearSelection(event) {
    if (!this.selectedEntry) return

    const cover = this.selectedEntry.querySelector("[data-bookshelf-cover]")
    this.selectEntry(null)
    if (event?.type === "keydown" || event?.detail === 0) cover?.focus({ preventScroll: true })
  }

  preventCoverContextMenu(event) {
    if (this.touchInput && (this.holdingCover || event.pointerType === "touch")) event.preventDefault()
  }

  startDrag() {
    this.dragStartOrder = this.entries()
    this.dragStartWidth = window.innerWidth
    if (this.touchInput && Sortable.ghost) Sortable.ghost.inert = true
    this.syncControls()
  }

  endDrag(event) {
    const previousOrder = this.dragStartOrder
    this.dragStartOrder = null
    if (!previousOrder) return

    const gesture = event.originalEvent?.type
    const cancelled = gesture === "pointercancel" || gesture === "touchcancel" || (this.touchInput && gesture !== "touchend")
    if (cancelled || this.dragStartWidth !== window.innerWidth || event.from !== event.to) {
      this.restoreOrder(previousOrder)
    } else if (event.oldIndex !== event.newIndex) {
      if (this.touchInput) {
        this.saveMobileOrder(previousOrder)
        return
      }
      this.reorder()
    }
    this.syncControls()
  }

  syncControls() {
    if (!this.hasControlsTarget) return

    const entries = this.entries()
    const index = entries.indexOf(this.selectedEntry)
    this.controlsTarget.classList.toggle("hidden", index < 0)
    this.spacerTarget.classList.toggle("hidden", index < 0)
    if (index < 0) return

    const busy = this.saving || this.holdingCover || !!this.dragStartOrder
    const title = this.selectedEntry.querySelector("[data-bookshelf-cover]").getAttribute("aria-label")
    this.selectedStatusTarget.textContent = `${title} (${index + 1}/${entries.length})`
    this.upButtonTarget.setAttribute("aria-label", this.moveUpLabelValue.replace("%{title}", () => title))
    this.downButtonTarget.setAttribute("aria-label", this.moveDownLabelValue.replace("%{title}", () => title))
    this.upButtonTarget.disabled = busy || index === 0
    this.downButtonTarget.disabled = busy || index === entries.length - 1
  }

  moveUp(event) {
    this.moveEntry(event.currentTarget, -1)
  }

  moveDown(event) {
    this.moveEntry(event.currentTarget, 1)
  }

  async moveEntry(button, direction) {
    if (this.saving || Sortable.dragged) return

    const previousOrder = this.entries()
    const entry = this.selectedEntry
    const index = previousOrder.indexOf(entry)
    const neighbor = previousOrder[index + direction]
    if (index < 0 || !neighbor) return

    if (direction < 0) {
      this.listTarget.insertBefore(entry, neighbor)
    } else {
      this.listTarget.insertBefore(neighbor, entry)
    }
    if (await this.saveMobileOrder(previousOrder) && this.selectedEntry === entry) {
      const nextButton = button.disabled ? this.controlsTarget.querySelector("button:not(:disabled)") : button
      nextButton?.focus({ preventScroll: true })
    }
  }

  async saveMobileOrder(previousOrder) {
    this.saving = true
    this.sortable.option("disabled", true)
    this.syncControls()

    if (!await this.reorder(previousOrder)) return false

    this.saving = false
    this.sortable?.option("disabled", false)
    this.syncControls()
    return true
  }

  restoreOrder(previousOrder) {
    this.listTarget.append(...previousOrder)
  }

  async reorder(previousOrder) {
    const formData = new FormData()
    formData.append("bookshelf_id", this.bookshelfIdValue)
    this.entryIds().forEach((id) => formData.append("bookshelf_entry_ids[]", id))

    try {
      const response = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        body: formData,
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken()
        }
      })
      if (response.status !== 204) throw new Error("Reorder failed")
      return true
    } catch (_error) {
      if (previousOrder) this.restoreOrder(previousOrder)
      window.alert(this.errorMessageValue)
      window.location.reload()
      return false
    }
  }

  entries() {
    return Array.from(this.listTarget.children).filter((entry) => entry.dataset.bookshelfEntryId && entry !== Sortable.ghost)
  }

  entryIds() {
    return this.entries().map((entry) => entry.dataset.bookshelfEntryId)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
