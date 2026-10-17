import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["actionBar", "applyButton", "bottomSpacer", "cancelButton", "controls", "editingStatus", "list", "modeButton"]
  static values = {
    bookshelfId: Number,
    reorderUrl: String
  }

  connect() {
    this.editing = false
    this.saving = false
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => this.syncBreakpoint()
    if (this.desktopQuery.addEventListener) {
      this.desktopQuery.addEventListener("change", this.handleBreakpointChange)
    } else {
      this.desktopQuery.addListener(this.handleBreakpointChange)
    }
    this.syncBreakpoint()
  }

  disconnect() {
    if (this.desktopQuery.removeEventListener) {
      this.desktopQuery.removeEventListener("change", this.handleBreakpointChange)
    } else {
      this.desktopQuery.removeListener(this.handleBreakpointChange)
    }
    this.sortable?.destroy()
  }

  syncBreakpoint() {
    if (this.editing && !this.saving) this.restoreOrder()
    if (!this.saving) this.editing = false
    this.syncControls()

    if (this.desktopQuery.matches) {
      if (this.sortable) return

      this.sortable = Sortable.create(this.listTarget, {
        animation: 120,
        handle: "[data-bookshelf-entries-sort-handle]",
        draggable: "[data-bookshelf-entry-id]",
        filter: "a, button, input, select, textarea, summary, details, form",
        preventOnFilter: false,
        onEnd: (event) => this.handleEnd(event)
      })
    } else if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  startEditing() {
    if (this.editing || this.desktopQuery.matches || this.saving) return

    this.initialEntryIds = this.entryIds()
    this.editing = true
    this.syncControls()
  }

  cancelEditing() {
    if (!this.editing || this.saving) return

    this.restoreOrder()
    this.editing = false
    this.syncControls()
    this.modeButtonTarget.focus()
  }

  restoreOrder() {
    const entriesById = new Map(this.entries().map((entry) => [ entry.dataset.bookshelfEntryId, entry ]))
    this.initialEntryIds.forEach((id) => this.listTarget.append(entriesById.get(id)))
  }

  async applyOrder() {
    if (!this.editing || this.saving || this.desktopQuery.matches || !this.hasChanges()) return

    this.saving = true
    this.syncControls()

    if (await this.reorder()) {
      this.saving = false
      this.editing = false
      this.syncControls()
      this.modeButtonTarget.focus()
    }
  }

  hasChanges() {
    if (!this.editing) return false

    const currentIds = this.entryIds()
    return this.initialEntryIds.some((id, index) => currentIds[index] !== id)
  }

  syncControls() {
    if (this.hasModeButtonTarget) {
      this.modeButtonTarget.classList.toggle("hidden", this.editing)
      this.editingStatusTarget.classList.toggle("hidden", !this.editing)
      this.actionBarTarget.classList.toggle("hidden", !this.editing)
      this.bottomSpacerTarget.classList.toggle("hidden", !this.editing)
      this.cancelButtonTarget.disabled = this.saving
      this.applyButtonTarget.disabled = this.saving || !this.hasChanges()
    }

    const entries = this.entries()
    this.controlsTargets.forEach((controls, index) => {
      const visible = this.editing && !this.desktopQuery.matches
      controls.classList.toggle("hidden", !visible)
      controls.classList.toggle("flex", visible)
      const [upButton, downButton] = controls.querySelectorAll("button")
      upButton.disabled = this.saving || index === 0
      downButton.disabled = this.saving || index === entries.length - 1
    })
  }

  moveUp(event) {
    this.moveEntry(event, -1)
  }

  moveDown(event) {
    this.moveEntry(event, 1)
  }

  moveEntry(event, direction) {
    if (!this.editing || this.saving || this.desktopQuery.matches) return

    const button = event.currentTarget
    const entry = button.closest("[data-bookshelf-entry-id]")
    const entries = this.entries()
    const index = entries.indexOf(entry)
    const neighbor = entries[index + direction]
    if (!neighbor) return

    if (direction < 0) {
      this.listTarget.insertBefore(entry, neighbor)
    } else {
      this.listTarget.insertBefore(neighbor, entry)
    }
    this.syncControls()
    if (!button.disabled) button.focus()
  }

  handleEnd(event) {
    if (event.from !== event.to || event.oldIndex === event.newIndex) return

    this.reorder()
  }

  async reorder() {
    const formData = new FormData()
    formData.append("bookshelf_id", this.bookshelfIdValue)
    this.entryIds().forEach((id) => formData.append("bookshelf_entry_ids[]", id))

    try {
      const response = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        body: formData,
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "X-CSRF-Token": this.csrfToken()
        }
      })
      if (!response.ok) throw new Error("Reorder failed")
      return true
    } catch (_error) {
      window.location.reload()
      return false
    }
  }

  entries() {
    return Array.from(this.listTarget.querySelectorAll("[data-bookshelf-entry-id]"))
  }

  entryIds() {
    return this.entries().map((entry) => entry.dataset.bookshelfEntryId)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
