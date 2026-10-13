import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "counter", "errors", "serverErrors", "warning"]
  static values = { limit: Number, message: String }

  connect() {
    this.update()
  }

  update() {
    const length = Array.from(this.inputTarget.value.replace(/\r\n?/g, "\n")).length
    const overLimit = length > this.limitValue
    this.counterTarget.textContent = `${length} / ${this.limitValue}`
    this.counterTarget.classList.toggle("text-red-700", overLimit)
    this.counterTarget.classList.toggle("text-stone-400", !overLimit)
    this.warningTarget.hidden = !overLimit
    this.errorsTarget.hidden = !overLimit && this.serverErrorsTarget.textContent.trim() === ""
    this.inputTarget.setCustomValidity(overLimit ? this.messageValue : "")
  }

  invalid(event) {
    if (this.inputTarget.validity.customError) {
      event.preventDefault()
      this.inputTarget.focus()
    }
  }

  reset(event) {
    if (event.target.contains(this.element)) {
      requestAnimationFrame(() => this.update())
    }
  }
}
