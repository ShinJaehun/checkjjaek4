import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame"]

  open(event) {
    const link = event.target.closest("a[data-book-search-modal]")
    if (!link || event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return

    event.preventDefault()
    this.opener = link
    const url = new URL(link.href)
    url.searchParams.set("modal", "1")
    this.frameTarget.src = url.href
    this.previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    this.dialogTarget.showModal()
  }

  loaded() {
    if (this.dialogTarget.open) this.frameTarget.querySelector('input[name="query"]')?.focus()
  }

  missing(event) {
    event.preventDefault()
    window.location.assign(event.detail.response.url)
  }

  cancel(event) {
    event.preventDefault()
    this.close()
  }

  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const rect = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.close()
  }

  close() {
    if (!this.hasDialogTarget || !this.dialogTarget.open) return
    this.dialogTarget.close()
    document.body.style.overflow = this.previousOverflow || ""
    if (this.opener?.isConnected) this.opener.focus()
  }

  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) document.body.style.overflow = this.previousOverflow || ""
  }
}
