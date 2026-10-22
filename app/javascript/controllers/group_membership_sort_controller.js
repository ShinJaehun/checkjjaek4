import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["list", "item"]

  connect() {
    this.desktopQuery = window.matchMedia("(min-width: 768px)")
    this.handleBreakpointChange = () => this.syncBreakpoint()
    this.desktopQuery.addEventListener("change", this.handleBreakpointChange)
    this.syncBreakpoint()
    this.syncButtons()
  }

  disconnect() {
    this.desktopQuery.removeEventListener("change", this.handleBreakpointChange)
    this.sortable?.destroy()
    this.sortable = null
  }

  syncBreakpoint() {
    if (this.desktopQuery.matches && !this.sortable) {
      this.sortable = Sortable.create(this.listTarget, {
        animation: 120,
        chosenClass: "md:cursor-grabbing",
        draggable: "[data-group-membership-sort-target='item']",
        onEnd: () => this.syncButtons()
      })
    } else if (!this.desktopQuery.matches && this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  moveUp(event) {
    this.moveItem(event, -1)
  }

  moveDown(event) {
    this.moveItem(event, 1)
  }

  moveItem(event, direction) {
    const button = event.currentTarget
    const item = button.closest("[data-group-membership-sort-target='item']")
    const items = this.itemTargets
    const neighbor = items[items.indexOf(item) + direction]
    if (!neighbor) return

    if (direction < 0) this.listTarget.insertBefore(item, neighbor)
    else this.listTarget.insertBefore(neighbor, item)
    this.syncButtons()

    const focusButton = button.disabled ? item.querySelector("button:not(:disabled)") : button
    focusButton?.focus()
  }

  syncButtons() {
    const items = this.itemTargets
    items.forEach((item, index) => {
      item.querySelector("[data-group-membership-sort-direction='up']").disabled = index === 0
      item.querySelector("[data-group-membership-sort-direction='down']").disabled = index === items.length - 1
    })
  }
}
