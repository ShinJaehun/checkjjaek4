import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "append",
    "entry",
    "list",
    "moveButton",
    "movePanel",
    "removeButton",
    "selectedCount",
    "selectedIds",
    "selectionBar",
    "selectionCheckbox",
    "selectionCheckboxWrapper",
    "sheetCloseButton",
    "sheetSelectedCount"
  ]
  static values = {
    organize: Boolean,
    moveErrorMessage: String,
    reorderErrorMessage: String,
    reorderUrl: String,
    removeConfirmation: String,
    bulkRemoveConfirmation: String,
    uiSourceBookshelfId: Number,
    uiTargetBookshelfId: Number
  }

  connect() {
    this.sortables = []
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => {
      if (!this.organizeValue) this.syncMode()
    }
    this.addBreakpointListener()
    this.syncMode()
  }

  disconnect() {
    if (this.hasMovePanelTarget && !this.movePanelTarget.classList.contains("hidden")) {
      document.body.style.overflow = this.previousBodyOverflow
    }
    this.removeBreakpointListener()
    this.destroySortables()
  }

  createSortable(element) {
    return Sortable.create(element, {
      animation: 120,
      group: "bookshelf-transfer",
      handle: "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button:not([data-bookshelf-cover]), input, select, textarea, summary, details, form, dialog",
      preventOnFilter: false,
      onStart: (event) => this.startDragging(event),
      onAdd: (event) => this.moveEntry(event),
      onEnd: (event) => this.finishDragging(event)
    })
  }

  syncMode() {
    const selecting = this.organizeValue || !this.desktopQuery.matches
    this.selectionList = selecting ? this.listTarget : null
    this.syncSortables()
    this.selectionBarTarget.classList.toggle("hidden", !selecting)
    this.element.classList.toggle("pb-32", selecting)

    this.selectionCheckboxWrapperTargets.forEach((wrapper) => {
      wrapper.classList.toggle("hidden", !selecting)
      wrapper.classList.toggle("inline-flex", selecting)
    })
    this.entryTargets.forEach((entry) => {
      const cover = entry.querySelector("[data-bookshelf-cover]")
      cover.classList.toggle("md:cursor-grab", !selecting)
      if (selecting) {
        cover.removeAttribute("aria-haspopup")
      } else {
        cover.setAttribute("aria-haspopup", "dialog")
        cover.removeAttribute("aria-pressed")
      }
    })
    this.clearSelection()
  }

  selectFromCover(event) {
    if (!this.selectionList) return

    event.stopImmediatePropagation()
    const entry = event.currentTarget.closest("[data-bookshelf-entry-id]")
    if (entry.parentElement !== this.selectionList) return

    const checkbox = this.checkboxForEntry(entry)
    checkbox.checked = !checkbox.checked
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

  syncSelection() {
    const selectedIds = this.selectedEntryIds()

    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = selectedIds.length
    }

    if (this.hasSheetSelectedCountTarget) {
      this.sheetSelectedCountTarget.textContent = selectedIds.length
    }

    if (this.hasMoveButtonTarget) {
      this.moveButtonTarget.disabled = selectedIds.length === 0
    }

    this.selectedIdsTargets.forEach((target) => {
      target.replaceChildren(...selectedIds.map((id) => this.hiddenEntryIdInput(id)))
    })

    if (this.hasRemoveButtonTarget) {
      this.removeButtonTarget.disabled = selectedIds.length === 0
      this.removeButtonTarget.dataset.turboConfirm = selectedIds.length > 1
        ? this.bulkRemoveConfirmationValue.replace("%{books_count}", selectedIds.length)
        : this.removeConfirmationValue
    }

    if (selectedIds.length === 0) {
      this.closeMovePanel()
    }

    this.entryTargets.forEach((entry) => {
      const selectable = entry.parentElement === this.selectionList
      const selected = selectable && this.checkboxForEntry(entry).checked
      if (selectable) {
        entry.querySelector("[data-bookshelf-cover]").setAttribute("aria-pressed", selected)
      }

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
    if (this.selectionList || !this.draggingEntryId) return

    event.preventDefault()
  }

  async dropOnAppend(event) {
    event.preventDefault()

    const targetBookshelfId = event.currentTarget.dataset.bookshelfTransferBookshelfId
    if (this.selectionList || !this.draggingEntryId || !targetBookshelfId) return
    if (this.draggedFromBookshelfId === targetBookshelfId) return

    await this.move(this.draggingEntryId, targetBookshelfId, null)
  }

  async moveEntry(event) {
    if (event.from === event.to) return

    const entryId = event.item.dataset.bookshelfEntryId
    const targetBookshelfId = event.to.dataset.bookshelfTransferBookshelfId
    const beforeEntryId = event.item.nextElementSibling?.dataset.bookshelfEntryId

    if (!entryId || !targetBookshelfId) {
      this.reloadAfterFailure(this.moveErrorMessageValue)
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
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken()
        }
      })

      const result = await response.json()
      if (!response.ok || !result.location) {
        this.reloadAfterFailure(result.error || this.moveErrorMessageValue)
        return
      }

      window.location.href = result.location
    } catch (_error) {
      this.reloadAfterFailure(this.moveErrorMessageValue)
    }
  }

  async finishDragging(event) {
    this.draggingEntryId = null
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
    } catch (_error) {
      this.reloadAfterFailure(this.reorderErrorMessageValue)
    }
  }

  reloadAfterFailure(message) {
    window.alert(message)
    window.location.reload()
  }

  entryIds(list) {
    return Array.from(list.querySelectorAll("[data-bookshelf-entry-id]")).map((entry) => entry.dataset.bookshelfEntryId)
  }

  sameEntryOrder(previousIds, currentIds) {
    if (!previousIds) return false
    if (previousIds.length !== currentIds.length) return false

    return previousIds.every((id, index) => id === currentIds[index])
  }

  selectedEntryIds() {
    const checked = this.selectionList?.querySelectorAll("input[name^='transfer_selection_']:checked")
    return Array.from(checked ?? [], (checkbox) => checkbox.value)
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

  syncSortables() {
    if (this.selectionList) {
      this.destroySortables()
    } else if (this.sortables.length === 0) {
      this.sortables = this.listTargets.map((list) => this.createSortable(list))
    }
  }

  destroySortables() {
    this.draggingEntryId = null
    this.sortables?.forEach((sortable) => sortable.destroy())
    this.sortables = []
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

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
