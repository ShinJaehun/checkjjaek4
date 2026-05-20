import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["append", "list"]
  static values = {
    reorderUrl: String,
    uiSourceBookshelfId: Number,
    uiTargetBookshelfId: Number
  }

  connect() {
    this.sortables = this.listTargets.map((list) => this.createSortable(list))
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
  }

  createSortable(element) {
    return Sortable.create(element, {
      animation: 120,
      group: "bookshelf-transfer",
      handle: "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button, input, select, textarea, summary, details, form",
      preventOnFilter: false,
      onStart: (event) => this.startDragging(event),
      onAdd: (event) => this.moveEntry(event),
      onEnd: (event) => this.reorderWithinShelf(event)
    })
  }

  startDragging(event) {
    this.draggingEntryId = event.item.dataset.bookshelfEntryId
    this.draggedFromBookshelfId = event.from.dataset.bookshelfTransferBookshelfId
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
    if (event.oldIndex === event.newIndex) return

    const bookshelfId = event.to.dataset.bookshelfTransferBookshelfId
    if (!bookshelfId) return

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

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
