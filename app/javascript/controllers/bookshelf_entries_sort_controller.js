import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    bookshelfId: Number,
    reorderUrl: String
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 120,
      handle: "[data-bookshelf-entries-sort-handle]",
      draggable: "[data-bookshelf-entry-id]",
      filter: "a, button, input, select, textarea, summary, details, form",
      preventOnFilter: false,
      onEnd: (event) => this.handleEnd(event)
    })
  }

  disconnect() {
    if (this.sortable) this.sortable.destroy()
  }

  handleEnd(event) {
    if (event.from !== event.to) return
    if (event.oldIndex === event.newIndex) return

    this.reorder()
  }

  async reorder() {
    const formData = new FormData()
    formData.append("bookshelf_id", this.bookshelfIdValue)
    this.entryIds().forEach((id) => formData.append("bookshelf_entry_ids[]", id))

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

  entryIds() {
    return Array.from(this.element.querySelectorAll("[data-bookshelf-entry-id]")).map((entry) => entry.dataset.bookshelfEntryId)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
