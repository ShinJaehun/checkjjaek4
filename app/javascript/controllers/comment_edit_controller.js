import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["actions", "display", "form"]

  open() {
    this.actionsTarget.classList.add("hidden")
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.formTarget.querySelector("textarea")?.focus()
  }

  cancel() {
    this.formTarget.querySelector("form")?.reset()
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
    this.actionsTarget.classList.remove("hidden")
  }
}
