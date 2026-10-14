import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "sticker", "message"]
  static values = { url: String, saving: String, saved: String, error: String }

  connect() {
    this.queue = []
    this.saving = false
    this.confirmed = {
      status: this.statusTargets.find(input => input.checked)?.value || null,
      sticker_definition_ids: this.stickerTargets.filter(input => input.checked).map(input => Number(input.value))
    }
  }

  changeStatus(event) {
    this.enqueue({ "bookshelf_entry[status]": event.target.value })
  }

  changeSticker(event) {
    this.enqueue({ sticker_definition_id: event.target.value, sticker_selected: event.target.checked })
  }

  enqueue(attributes) {
    this.queue.push(attributes)
    this.save()
  }

  async save() {
    if (this.saving) return

    this.saving = true
    this.element.setAttribute("aria-busy", "true")
    this.messageTarget.classList.remove("text-red-700")
    this.messageTarget.textContent = this.savingValue

    try {
      // Send one mutation at a time so rapid clicks reach Rails in click order.
      while (this.queue.length) {
        const attributes = this.queue.shift()
        const response = await fetch(this.urlValue, {
          method: "PATCH",
          credentials: "same-origin",
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
          },
          body: new URLSearchParams(attributes)
        })
        const state = await response.json()
        if (!response.ok) throw new Error(state.error || this.errorValue)
        this.confirmed = state
      }
      this.messageTarget.textContent = this.savedValue
    } catch (error) {
      this.queue = []
      this.statusTargets.forEach(input => { input.checked = input.value === (this.confirmed.status || "") })
      this.stickerTargets.forEach(input => { input.checked = this.confirmed.sticker_definition_ids.includes(Number(input.value)) })
      this.messageTarget.classList.add("text-red-700")
      this.messageTarget.textContent = this.errorValue
    } finally {
      this.saving = false
      this.element.removeAttribute("aria-busy")
    }
  }
}
