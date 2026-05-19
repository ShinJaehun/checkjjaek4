import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["list"]
  static values = {
    reorderUrl: String,
    view: String
  }

  connect() {
    this.sortables = this.listTargets.map((list) => Sortable.create(list, {
      animation: 120,
      group: "bookshelf-entries-cross-shelf-spike",
      handle: "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button, input, select, textarea, summary, details, form",
      preventOnFilter: false,
      onAdd: (event) => this.moveAcrossShelves(event),
      onEnd: (event) => this.reorderWithinShelf(event)
    }))
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
  }

  async moveAcrossShelves(event) {
    if (event.from === event.to) return

    document.documentElement.dataset.bookshelfDndExternalMove = "true"

    const entryId = event.item.dataset.bookshelfEntryId
    const targetBookshelfId = event.to.dataset.crossShelfSortableBookshelfId
    const beforeEntryId = event.item.nextElementSibling?.dataset.bookshelfEntryId

    if (!entryId || !targetBookshelfId) {
      window.location.reload()
      return
    }

    const formData = new FormData()
    formData.append("bookshelf_id", targetBookshelfId)
    formData.append("return_to", "library")
    formData.append("sort", "manual")
    if (this.hasViewValue) formData.append("view", this.viewValue)
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

    const bookshelfId = event.to.dataset.crossShelfSortableBookshelfId
    if (!bookshelfId) return

    const formData = new FormData()
    formData.append("bookshelf_id", bookshelfId)
    this.entryIds(event.to).forEach((id) => formData.append("bookshelf_entry_ids[]", id))

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
