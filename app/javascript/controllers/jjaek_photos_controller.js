import { Controller } from "@hotwired/stimulus"

// Files stay in this tab's memory across Turbo visits, never in localStorage.
const drafts = new Map()
const allowedTypes = ["image/jpeg", "image/png", "image/webp"]
const maxBytes = 5 * 1024 * 1024

export default class extends Controller {
  static targets = ["picker", "uploads", "previews", "removals", "error", "clientError", "serverErrors", "processing", "guidance"]
  static values = { invalidMessage: String, sizeMessage: String, formatMessage: String, limitMessage: String, removeMessage: String }

  connect() {
    this.form = this.element.querySelector("form")
    this.discardDraftOnVisit = false
    this.key = [this.element.dataset.authorId, this.form.getAttribute("action"), this.element.dataset.editingId,
      this.element.dataset.groupId, this.element.dataset.targetUserId,
      this.form.querySelector("[name='book_context_id'], [name='book_context_token']")?.value].join(":")
    this.urls = []
    if (!this.files) {
      this.files = []
      this.removed = []
      this.guidanceShown = false
      const draft = drafts.get(this.key)
      if (draft) {
        this.files = draft.files
        this.removed = draft.removed
        this.guidanceShown = draft.guidanceShown === true
        const textarea = this.form.querySelector("textarea")
        textarea.value = draft.content
        textarea.dispatchEvent(new Event("input", { bubbles: true }))
        this.form.querySelectorAll("[name='jjaek[visibility]']").forEach(input => { input.checked = input.value === draft.visibility })
        if (draft.books) this.element.querySelector("#jjaek-attached-books")?.replaceChildren(...draft.books.map(node => node.cloneNode(true)))
      }
    }
    this.render()
    this.updateErrors()
    this.submitGuard = event => {
      if (this.busy) event.preventDefault()
      else this.remember()
    }
    this.form.addEventListener("submit", this.submitGuard)
  }

  disconnect() {
    this.remember()
    this.dismissGuidance()
    this.releaseUrls()
    this.form.removeEventListener("submit", this.submitGuard)
  }

  choose() {
    if (this.busy) return
    if (this.guidanceShown) return this.pickerTarget.click()

    this.guidanceShown = true
    this.remember()
    this.guidanceTarget.showModal()
  }

  dismissGuidance(event) {
    if (event?.type === "cancel") event.preventDefault()
    if (this.hasGuidanceTarget && this.guidanceTarget.open) this.guidanceTarget.close()
  }

  confirmGuidance() {
    this.dismissGuidance()
    this.pickerTarget.click()
  }

  async select() {
    const selected = Array.from(this.pickerTarget.files)
    this.pickerTarget.value = ""
    if (this.busy || !selected.length) return
    this.clearClientError()
    if (this.count + selected.length > 4) return this.fail(this.limitMessageValue, "limit")
    if (selected.some(file => file.size > maxBytes)) return this.fail(this.sizeMessageValue, "too_large")
    if (selected.some(file => !allowedTypes.includes(file.type))) return this.fail(this.formatMessageValue, "unsupported_format")
    if (selected.some(file => !file.size)) return this.fail(this.invalidMessageValue)
    this.busy = true
    this.processingTarget.hidden = false
    const converted = []
    try {
      // Decode one image at a time to bound browser memory as well.
      for (const file of selected) converted.push(await this.optimize(file))
      this.files.push(...converted)
      this.render()
      this.photosChanged()
      this.remember()
    } catch (error) {
      if (error?.photoCode === "too_large") this.fail(this.sizeMessageValue, "too_large")
      else this.fail(this.invalidMessageValue)
    } finally {
      this.busy = false
      this.processingTarget.hidden = true
    }
  }

  async optimize(file) {
    const bitmap = await createImageBitmap(file)
    try {
      const scale = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height))
      const canvas = document.createElement("canvas")
      canvas.width = Math.max(1, Math.round(bitmap.width * scale))
      canvas.height = Math.max(1, Math.round(bitmap.height * scale))
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      // Canvas re-encoding removes EXIF, including location and camera data.
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/webp", 0.85))
      canvas.width = canvas.height = 0
      if (!blob) throw new Error("Invalid photo")
      if (blob.size > maxBytes) {
        const error = new Error("Photo too large")
        error.photoCode = "too_large"
        throw error
      }
      return new File([blob], `photo-${crypto.randomUUID()}.webp`, { type: blob.type })
    } finally {
      bitmap.close()
    }
  }

  get count() {
    return this.previewsTarget.querySelectorAll("[data-photo-id]:not([hidden])").length + this.files.length
  }

  remove(event) {
    if (this.busy) return
    const row = event.target.closest("[data-photo-id], [data-new-photo]")
    const visibleRows = Array.from(this.previewsTarget.children).filter(item => !item.hidden)
    const index = visibleRows.indexOf(row)
    if (row.dataset.photoId) this.removed.push(row.dataset.photoId)
    else this.files.splice(Number(row.dataset.newPhoto), 1)
    this.render()
    this.photosChanged()
    this.remember()
    const remainingRows = Array.from(this.previewsTarget.children).filter(item => !item.hidden)
    const nextRow = remainingRows[Math.min(index, remainingRows.length - 1)]
    const nextButton = nextRow?.querySelector("button") || this.element.querySelector("[data-action='jjaek-photos#choose']")
    nextButton?.focus({ preventScroll: true })
  }

  render() {
    this.releaseUrls()
    this.previewsTarget.querySelectorAll("[data-new-photo]").forEach(node => node.remove())
    this.previewsTarget.querySelectorAll("[data-photo-id]").forEach(node => { node.hidden = this.removed.includes(node.dataset.photoId) })
    this.removalsTarget.replaceChildren(...this.removed.map(value => {
      const input = document.createElement("input")
      Object.assign(input, { type: "hidden", name: "jjaek[remove_photo_ids][]", value })
      return input
    }))
    const transfer = new DataTransfer()
    this.files.forEach((file, index) => {
      transfer.items.add(file)
      const row = document.createElement("div")
      row.dataset.newPhoto = index
      row.className = "jjaek-photo-preview"
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      this.urls.push(img.src)
      Object.assign(img, { alt: file.name, draggable: false, className: "h-32 w-full rounded-xl object-contain bg-stone-100" })
      const button = document.createElement("button")
      Object.assign(button, { type: "button", className: "jjaek-photo-remove" })
      button.setAttribute("aria-label", this.removeMessageValue)
      button.dataset.action = "jjaek-photos#remove"
      const icon = document.createElement("span")
      icon.textContent = "×"
      icon.setAttribute("aria-hidden", "true")
      button.append(icon)
      row.append(img, button)
      this.previewsTarget.append(row)
    })
    this.uploadsTarget.files = transfer.files
  }

  remember(event) {
    if (this.busy && event?.type === "turbo:before-visit") event.preventDefault()

    // 같은 페이지를 새로 방문하면 초안을 폐기한다.
    // 책 선택 창에서 돌아오는 방문은 기존 초안을 유지한다.
    if (event?.type === "turbo:before-visit" &&
        new URL(event.detail.url, window.location.href).href === window.location.href &&
        document.querySelector("#book-selection-window")?.hidden !== false) {
      drafts.delete(this.key)
      this.discardDraftOnVisit = true
    }
    if (this.discardDraftOnVisit) return

    if (this.completed || !this.form || !this.files) return
    drafts.set(this.key, {
      files: this.files, removed: this.removed, guidanceShown: this.guidanceShown,
      content: this.form.querySelector("textarea").value,
      visibility: this.form.querySelector("[name='jjaek[visibility]']:checked")?.value,
      books: Array.from(this.element.querySelector("#jjaek-attached-books")?.childNodes || [], node => node.cloneNode(true))
    })
  }

  submitted(event) {
    if (event.target !== this.form || !event.detail.success) return
    this.completed = true
    drafts.delete(this.key)
    this.files = []
    this.guidanceShown = false
    this.releaseUrls()
  }

  received(event) {
    if (event.target !== this.form) return
    const response = event.detail.fetchResponse
    // Clear before Turbo connects the destination's fresh composer. submit-end
    // can arrive after the originating form has already been disconnected.
    if (response.succeeded && response.redirected) {
      this.completed = true
      drafts.delete(this.key)
      this.files = []
      this.guidanceShown = false
      this.releaseUrls()
    }
  }

  releaseUrls() {
    this.urls?.forEach(url => URL.revokeObjectURL(url))
    this.urls = []
  }

  fail(message, code = "invalid") {
    this.clientErrorTarget.textContent = message
    this.clientErrorTarget.dataset.photoErrorCode = code
    this.clientErrorTarget.hidden = false
    this.updateErrors()
  }

  clearClientError() {
    this.clientErrorTarget.textContent = ""
    this.clientErrorTarget.hidden = true
    this.updateErrors()
  }

  photosChanged() {
    this.clearClientError()
    this.serverErrorsTarget.querySelectorAll("[data-photo-error-code]").forEach(error => {
      // Quotas are checked by the server. They cease to apply when the user
      // removes all new uploads; changing a file alone cannot prove capacity.
      const quotaError = ["daily_limit", "retained_limit", "storage_limit", "disabled"].includes(error.dataset.photoErrorCode)
      if (quotaError && this.files.length > 0) return
      if (error.dataset.photoErrorCode === "limit" && this.count > 4) return
      if (error.dataset.photoErrorCode === "invalid_removal" && this.removed.length > 0) return
      error.remove()
    })
    this.updateErrors()
  }

  updateErrors() {
    this.errorTarget.hidden = this.clientErrorTarget.hidden && !this.serverErrorsTarget.querySelector("[data-photo-error-code]")
  }

  prevent(event) { event.preventDefault() }
}
