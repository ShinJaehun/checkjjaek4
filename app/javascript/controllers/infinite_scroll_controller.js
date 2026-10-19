import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["pagination", "link", "loading", "error"]

  connect() {
    this.connected = true
    if ("IntersectionObserver" in window) {
      this.observer = new IntersectionObserver(entries => {
        if (entries.some(entry => entry.isIntersecting) && !this.failed) this.load()
      }, { rootMargin: "200px" })
      this.observePagination()
    }
  }

  disconnect() {
    this.connected = false
    this.observer?.disconnect()
    this.abortController?.abort()
  }

  paginationTargetConnected() {
    this.observePagination()
  }

  paginationTargetDisconnected(element) {
    this.observer?.unobserve(element)
  }

  observePagination() {
    if (this.hasPaginationTarget && this.hasLinkTarget) this.observer?.observe(this.paginationTarget)
  }

  async load(event) {
    event?.preventDefault()
    if (this.loading || !this.hasLinkTarget || this.lastLoadedUrl === this.linkTarget.href) return

    const url = this.linkTarget.href
    this.loading = true
    this.failed = false
    this.loadingTarget.hidden = false
    this.errorTarget.hidden = true
    this.element.setAttribute("aria-busy", "true")
    this.abortController = new AbortController()
    try {
      const response = await fetch(url, {
        headers: { Accept: "text/vnd.turbo-stream.html", "X-Feed-Pagination": "true" },
        signal: this.abortController.signal
      })
      if (!response.ok || response.redirected || !response.headers.get("Content-Type")?.includes("text/vnd.turbo-stream.html")) {
        throw new Error("Feed request failed")
      }
      const html = await response.text()
      if (this.connected) {
        Turbo.renderStreamMessage(html)
        this.lastLoadedUrl = url
      }
    } catch (error) {
      if (error.name !== "AbortError" && this.connected) {
        this.failed = true
        this.errorTarget.hidden = false
      }
    } finally {
      this.loading = false
      if (this.connected) {
        this.element.removeAttribute("aria-busy")
        if (this.hasLoadingTarget) this.loadingTarget.hidden = true
        if (this.hasPaginationTarget) this.observer?.unobserve(this.paginationTarget)
        this.observePagination()
      }
    }
  }
}
