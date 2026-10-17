import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "append",
    "entry",
    "list",
    "moveButton",
    "movePanel",
    "selectedCount",
    "selectedIds",
    "selectionBar",
    "selectionCheckbox",
    "selectionCheckboxWrapper",
    "sheetCloseButton",
    "sheetSelectedCount"
  ]
  static values = {
    reorderUrl: String,
    uiSourceBookshelfId: Number,
    uiTargetBookshelfId: Number
  }

  connect() {
    this.sortables = []
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => this.resetForBreakpoint()
    this.addBreakpointListener()
    this.syncSortables()
    this.clearSelection()
  }

  disconnect() {
    if (this.hasMovePanelTarget && !this.movePanelTarget.classList.contains("hidden")) {
      document.body.style.overflow = this.previousBodyOverflow
    }
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

  toggleEntrySelection(event) {
    event?.stopPropagation()
    this.syncSelection()
  }

  clearSelection() {
    this.selectionCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    this.syncSelection()
  }

  openMovePanel(event) {
    if (!this.hasMovePanelTarget) return
    if (this.selectedEntryIds().length === 0) return

    this.movePanelOpener = event.currentTarget
    this.previousBodyOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    this.movePanelTarget.classList.remove("hidden")
    this.movePanelTarget.classList.add("flex")
    this.sheetCloseButtonTarget.focus()
  }

  closeMovePanel() {
    if (!this.hasMovePanelTarget || this.movePanelTarget.classList.contains("hidden")) return

    this.movePanelTarget.classList.add("hidden")
    this.movePanelTarget.classList.remove("flex")
    document.body.style.overflow = this.previousBodyOverflow
    this.movePanelOpener?.focus()
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) this.closeMovePanel()
  }

  handleMovePanelKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeMovePanel()
      return
    }

    if (event.key !== "Tab") return

    const buttons = Array.from(this.movePanelTarget.querySelectorAll("button:not([disabled])"))
    const first = buttons[0]
    const last = buttons[buttons.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  submitSourceSelect(event) {
    event.currentTarget.form.requestSubmit()
  }

  toggleCardSelection(event) {
    if (this.controlElement(event.target)) return

    if (this.desktopTransfer()) return

    const checkbox = this.checkboxForEntry(event.currentTarget)
    if (!checkbox) return

    event.preventDefault()
    checkbox.checked = !checkbox.checked
    this.syncSelection()
  }

  syncSelection() {
    const selectedIds = this.selectedEntryIds()
    const mobile = !this.desktopTransfer()

    if (this.hasSelectionBarTarget) {
      this.selectionBarTarget.classList.toggle("hidden", !mobile)
    }

    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = selectedIds.length
    }

    if (this.hasSheetSelectedCountTarget) {
      this.sheetSelectedCountTarget.textContent = selectedIds.length
    }

    if (this.hasMoveButtonTarget) {
      this.moveButtonTarget.disabled = selectedIds.length === 0
    }

    if (this.hasSelectedIdsTarget) {
      this.selectedIdsTarget.replaceChildren(
        ...selectedIds.map((id) => this.hiddenEntryIdInput(id))
      )
    }

    if (!mobile || selectedIds.length === 0) {
      this.closeMovePanel()
    }

    this.selectionCheckboxWrapperTargets.forEach((wrapper) => {
      wrapper.classList.toggle("hidden", !mobile)
      wrapper.classList.toggle("inline-flex", mobile)
    })

    this.entryTargets.forEach((entry) => {
      const checkbox = this.checkboxForEntry(entry)
      const selected = mobile && checkbox?.checked

      if (!checkbox) {
        this.clearEntrySelectionStyle(entry)
        return
      }

      entry.classList.toggle("border-stone-900", selected)
      entry.classList.toggle("bg-stone-50", selected)
      entry.classList.toggle("ring-2", selected)
      entry.classList.toggle("ring-stone-900", selected)
    })
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
    this.clearSelection()
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
