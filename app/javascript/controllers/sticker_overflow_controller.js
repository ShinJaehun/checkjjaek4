import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sticker", "summary"]
  static values = { extraNames: Array, summaryLabel: String }

  connect() {
    if (!this.hasSummaryTarget) return

    this.observer = new ResizeObserver(() => this.layout())
    this.observer.observe(this.element)
    this.layout()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  layout() {
    const availableWidth = this.element.getBoundingClientRect().width
    if (!availableWidth) return

    const stickers = this.stickerTargets
    stickers.forEach(sticker => { sticker.style.display = "" })
    this.summaryTarget.style.display = ""

    const widths = stickers.map(sticker => sticker.getBoundingClientRect().width)
    const gap = parseFloat(getComputedStyle(this.element).columnGap) || 0
    const total = stickers.length + this.extraNamesValue.length
    let visible = stickers.length

    // Reserve the summary's actual width before deciding how many icons fit.
    while (visible > 0) {
      const remaining = total - visible
      this.summaryTarget.textContent = `+${remaining}`
      const summaryWidth = remaining ? this.summaryTarget.getBoundingClientRect().width : 0
      const itemCount = visible + (remaining ? 1 : 0)
      const neededWidth = widths.slice(0, visible).reduce((sum, width) => sum + width, 0) +
        summaryWidth + gap * (itemCount - 1)
      if (neededWidth <= availableWidth) break
      visible -= 1
    }

    stickers.forEach((sticker, index) => { sticker.style.display = index < visible ? "" : "none" })
    const hiddenNames = stickers.slice(visible).map(sticker => sticker.firstElementChild.title)
      .concat(this.extraNamesValue)
    const remaining = hiddenNames.length
    this.summaryTarget.style.display = remaining ? "" : "none"
    this.summaryTarget.textContent = `+${remaining}`
    this.summaryTarget.title = hiddenNames.join(", ")
    this.summaryTarget.setAttribute("aria-label",
      `${this.summaryLabelValue.replace("{count}", String(remaining))}: ${hiddenNames.join(", ")}`)
  }
}
