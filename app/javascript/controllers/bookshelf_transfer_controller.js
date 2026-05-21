import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "append",
    "entry",
    "list",
    "movePanel",
    "selectedCount",
    "selectedIds",
    "selectionBar",
    "selectionCheckbox",
    "selectionCheckboxWrapper",
    "selectionModeButton"
  ]
  static values = {
    cancelSelectionLabel: String,
    reorderUrl: String,
    selectModeLabel: String,
    uiSourceBookshelfId: Number,
    uiTargetBookshelfId: Number
  }

  connect() {
    this.selectionMode = false
    this.sortables = []
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => this.resetForBreakpoint()
    this.addBreakpointListener()
    this.syncSortables()
    this.syncSelection()
  }

  disconnect() {
    this.removeBreakpointListener()
    this.destroySortables()
  }

  createSortable(element, options = {}) {
    return Sortable.create(element, {
      animation: 120,
      group: options.group || "bookshelf-transfer",
      handle: options.handle || "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button, input, select, textarea, summary, details, form",
      preventOnFilter: false,
      onStart: (event) => this.startDragging(event),
      onAdd: (event) => this.moveEntry(event),
      onEnd: (event) => this.reorderWithinShelf(event)
    })
  }

  toggleSelectionMode() {
    if (this.selectionMode) {
      this.exitSelectionMode()
    } else {
      this.enterSelectionMode()
    }
  }

  toggleEntrySelection(event) {
    event?.stopPropagation()
    this.syncSelection()
  }

  clearSelection() {
    this.exitSelectionMode()
  }

  toggleMovePanel() {
    if (!this.hasMovePanelTarget) return
    if (this.selectedEntryIds().length === 0) return

    this.movePanelTarget.classList.toggle("hidden")
    this.movePanelTarget.classList.toggle("grid")
  }

  submitSourceSelect(event) {
    event.currentTarget.form.requestSubmit()
  }

  toggleCardSelection(event) {
    if (this.controlElement(event.target)) return

    if (!this.selectionMode) return

    const checkbox = this.checkboxForEntry(event.currentTarget)
    if (!checkbox) return

    event.preventDefault()
    checkbox.checked = !checkbox.checked
    this.syncSelection()
  }

  syncSelection() {
    const selectedIds = this.selectedEntryIds()

    if (this.hasSelectionBarTarget) {
      this.selectionBarTarget.classList.toggle("hidden", !this.selectionMode || selectedIds.length === 0)
    }

    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = selectedIds.length
    }

    if (this.hasSelectedIdsTarget) {
      this.selectedIdsTarget.replaceChildren(
        ...selectedIds.map((id) => this.hiddenEntryIdInput(id))
      )
    }

    if ((!this.selectionMode || selectedIds.length === 0) && this.hasMovePanelTarget) {
      this.movePanelTarget.classList.add("hidden")
      this.movePanelTarget.classList.remove("grid")
    }

    this.selectionCheckboxWrapperTargets.forEach((wrapper) => {
      wrapper.classList.toggle("hidden", !this.selectionMode)
      wrapper.classList.toggle("inline-flex", this.selectionMode)
    })

    this.entryTargets.forEach((entry) => {
      const checkbox = this.checkboxForEntry(entry)
      const selected = checkbox?.checked

      if (!checkbox) {
        this.clearEntrySelectionStyle(entry)
        return
      }

      entry.classList.toggle("border-stone-900", selected)
      entry.classList.toggle("bg-stone-50", selected)
      entry.classList.toggle("ring-2", selected)
      entry.classList.toggle("ring-stone-900", selected)
    })

    if (this.hasSelectionModeButtonTarget) {
      this.selectionModeButtonTarget.textContent = this.selectionMode ? this.cancelSelectionLabelValue : this.selectModeLabelValue
    }
  }

  startDragging(event) {
    this.draggingEntryId = event.item.dataset.bookshelfEntryId
    this.draggedFromBookshelfId = event.from.dataset.bookshelfTransferBookshelfId
    this.draggedFromEntryIds = this.entryIds(event.from)
  }

  dragoverAppend(event) {
    if (!this.draggingEntryId) return

    event.preventDefault()
  }

  async dropOnAppend(event) {
    event.preventDefault()

    const targetBookshelfId = event.currentTarget.dataset.bookshelfTransferBookshelfId
    if (!this.draggingEntryId || !targetBookshelfId) return
    if (this.draggedFromBookshelfId === targetBookshelfId) return

    await this.move(this.draggingEntryId, targetBookshelfId, null)
  }

  async moveEntry(event) {
    if (event.from === event.to) return

    const entryId = event.item.dataset.bookshelfEntryId
    const targetBookshelfId = event.to.dataset.bookshelfTransferBookshelfId
    const beforeEntryId = event.item.nextElementSibling?.dataset.bookshelfEntryId

    if (!entryId || !targetBookshelfId) {
      window.location.reload()
      return
    }

    await this.move(entryId, targetBookshelfId, beforeEntryId)
  }

  async move(entryId, targetBookshelfId, beforeEntryId) {
    const formData = new FormData()
    formData.append("bookshelf_id", targetBookshelfId)
    formData.append("return_to", "library_transfer")
    formData.append("source_bookshelf_id", this.uiSourceBookshelfIdValue)
    formData.append("target_bookshelf_id", this.uiTargetBookshelfIdValue)
    if (beforeEntryId) formData.append("before_entry_id", beforeEntryId)

    try {
      const response = await fetch(`/bookshelf_entries/${entryId}/move`, {
        method: "PATCH",
        body: formData,
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "X-CSRF-Token": this.csrfToken()
        }
      })

      if (!response.ok) {
        window.location.reload()
        return
      }

      window.location.href = response.url
    } catch (_error) {
      window.location.reload()
    }
  }

  async reorderWithinShelf(event) {
    if (event.from !== event.to) return

    const bookshelfId = event.to.dataset.bookshelfTransferBookshelfId
    if (!bookshelfId) return
    if (this.sameEntryOrder(this.draggedFromEntryIds, this.entryIds(event.to))) return

    await this.reorderList(event.to, bookshelfId)
  }

  async reorderList(list, bookshelfId) {
    if (!list || !bookshelfId) return

    const formData = new FormData()
    formData.append("bookshelf_id", bookshelfId)
    this.entryIds(list).forEach((id) => formData.append("bookshelf_entry_ids[]", id))

    const response = await fetch(this.reorderUrlValue, {
      method: "PATCH",
      body: formData,
      credentials: "same-origin",
      headers: {
        Accept: "text/html",
        "X-CSRF-Token": this.csrfToken()
      }
    })

    if (!response.ok) window.location.reload()
  }

  entryIds(list) {
    return Array.from(list.querySelectorAll("[data-bookshelf-entry-id]")).map((entry) => entry.dataset.bookshelfEntryId)
  }

  sameEntryOrder(previousIds, currentIds) {
    if (!previousIds) return false
    if (previousIds.length !== currentIds.length) return false

    return previousIds.every((id, index) => id === currentIds[index])
  }

  selectedCheckboxes() {
    return Array.from(this.element.querySelectorAll("input[name^='transfer_selection_']:checked"))
  }

  selectedEntryIds() {
    return this.selectedCheckboxes().map((checkbox) => checkbox.value)
  }

  hiddenEntryIdInput(id) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "bookshelf_entry_ids[]"
    input.value = id
    return input
  }

  enterSelectionMode(entry = null) {
    this.selectionMode = true
    if (entry) {
      const checkbox = this.checkboxForEntry(entry)
      if (checkbox) checkbox.checked = true
    }
    this.syncSelection()
    this.syncSortables()
  }

  exitSelectionMode() {
    this.selectionMode = false
    this.selectionCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    this.element.querySelectorAll("[data-bookshelf-entry-id]").forEach((entry) => this.clearEntrySelectionStyle(entry))
    this.syncSelection()
    this.syncSortables()
  }

  checkboxForEntry(entry) {
    return entry.querySelector("input[name^='transfer_selection_']")
  }

  controlElement(element) {
    return element.closest("a, button, input, select, textarea, summary, details, form, label")
  }

  clearEntrySelectionStyle(entry) {
    entry.classList.remove("border-stone-900", "bg-stone-50", "ring-2", "ring-stone-900")
  }

  resetForBreakpoint() {
    this.exitSelectionMode()
    this.syncSortables()
  }

  syncSortables() {
    if (this.desktopTransfer()) {
      if (this.sortableMode === "desktop") return

      this.destroySortables()
      this.sortables = this.listTargets.map((list) => this.createSortable(list))
      this.sortableMode = "desktop"
    } else {
      this.destroySortables()
    }
  }

  destroySortables() {
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
    this.sortableMode = null
  }

  addBreakpointListener() {
    if (this.desktopQuery.addEventListener) {
      this.desktopQuery.addEventListener("change", this.handleBreakpointChange)
    } else {
      this.desktopQuery.addListener(this.handleBreakpointChange)
    }
  }

  removeBreakpointListener() {
    if (!this.desktopQuery) return

    if (this.desktopQuery.removeEventListener) {
      this.desktopQuery.removeEventListener("change", this.handleBreakpointChange)
    } else {
      this.desktopQuery.removeListener(this.handleBreakpointChange)
    }
  }

  desktopTransfer() {
    return this.desktopQuery?.matches ?? window.matchMedia("(min-width: 768px)").matches
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
