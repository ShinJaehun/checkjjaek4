import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["list", "body", "toggle"]
  static values = { reorderUrl: String }

  connect() {
    this.sortables = this.listTargets.map((list) => Sortable.create(list, {
      animation: 120,
      group: "bookshelf-organize",
      handle: "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button, input, select, textarea, summary, details, form",
      preventOnFilter: false,
      onStart: (event) => this.startDrag(event),
      onAdd: (event) => this.moveAcrossShelves(event),
      onEnd: (event) => this.finishDrag(event)
    }))
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
  }

  startDrag(event) {
    this.draggedEntryId = event.item.dataset.bookshelfEntryId
    this.sourceBookshelfId = event.from.dataset.bookshelfOrganizeBookshelfId
  }

  finishDrag(event) {
    if (event.from === event.to && event.oldIndex !== event.newIndex) this.reorder(event.to)
    this.draggedEntryId = null
    this.sourceBookshelfId = null
  }

  dragoverHeader(event) {
    if (!this.draggedEntryId) return
    event.preventDefault()
  }

  dropOnHeader(event) {
    if (!this.draggedEntryId) return

    event.preventDefault()
    const targetBookshelfId = event.currentTarget.closest("[data-bookshelf-organize-bookshelf-id]")?.dataset.bookshelfOrganizeBookshelfId
    if (!targetBookshelfId || targetBookshelfId === this.sourceBookshelfId) return

    this.move(this.draggedEntryId, targetBookshelfId)
  }

  toggleColumn(event) {
    const column = event.currentTarget.closest("[data-bookshelf-organize-target='column']")
    const body = column?.querySelector("[data-bookshelf-organize-target='body']")
    if (!body) return

    const collapsed = body.classList.toggle("hidden")
    event.currentTarget.textContent = collapsed ? "+" : "-"
  }

  moveAcrossShelves(event) {
    if (event.from === event.to) return

    const entryId = event.item.dataset.bookshelfEntryId
    const targetBookshelfId = event.to.dataset.bookshelfOrganizeBookshelfId
    const beforeEntryId = event.item.nextElementSibling?.dataset.bookshelfEntryId
    if (!entryId || !targetBookshelfId) {
      window.location.reload()
      return
    }

    this.move(entryId, targetBookshelfId, beforeEntryId)
  }

  async move(entryId, bookshelfId, beforeEntryId = null) {
    const formData = new FormData()
    formData.append("bookshelf_id", bookshelfId)
    formData.append("return_to", "library")
    formData.append("sort", "manual")
    formData.append("view", "compact")
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

  async reorder(list) {
    const bookshelfId = list.dataset.bookshelfOrganizeBookshelfId
    if (!bookshelfId) return

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
