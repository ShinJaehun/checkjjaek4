import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "links"]

  toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") !== "true"
    this.buttonTarget.setAttribute("aria-expanded", String(expanded))
    this.linksTargets.forEach((links) => {
      links.classList.toggle("hidden", !expanded)
      links.classList.toggle("flex", expanded)
    })
  }
}
