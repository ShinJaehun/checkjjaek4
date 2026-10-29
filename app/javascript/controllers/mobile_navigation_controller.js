import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "links"]

  toggle() {
    this.setExpanded(this.buttonTarget.getAttribute("aria-expanded") !== "true")
  }

  close() {
    if (this.buttonTarget.getAttribute("aria-expanded") === "true") this.buttonTarget.focus()
    this.setExpanded(false)
  }

  setExpanded(expanded) {
    this.buttonTarget.setAttribute("aria-expanded", String(expanded))
    this.linksTargets.forEach((links) => {
      links.classList.toggle("hidden", !expanded)
      links.classList.toggle("flex", expanded)
    })
  }
}
