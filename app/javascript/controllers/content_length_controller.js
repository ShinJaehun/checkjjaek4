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
    this.warningTarget.toggleAttribute("hidden", !overLimit)
    this.serverErrorsTarget.querySelectorAll('[data-content-error-type="blank"]').forEach(error => {
      error.toggleAttribute("hidden", this.inputTarget.value.trim().length > 0)
    })
    const visibleServerErrors = Array.from(this.serverErrorsTarget.children).filter(error => !error.hidden)
    this.serverErrorsTarget.toggleAttribute("hidden", visibleServerErrors.length === 0)
    this.errorsTarget.toggleAttribute("hidden", !overLimit && visibleServerErrors.length === 0)
    const contentInvalid = overLimit || visibleServerErrors.some(error => error.hasAttribute("data-content-error-type"))
    if (this.inputTarget.getAttribute("aria-invalid") !== String(contentInvalid)) {
      this.inputTarget.setAttribute("aria-invalid", String(contentInvalid))
    }
    const descriptions = new Set((this.inputTarget.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean))
    descriptions.delete(this.errorsTarget.id)
    if (contentInvalid) descriptions.add(this.errorsTarget.id)
    const describedBy = Array.from(descriptions).join(" ")
    if (this.inputTarget.getAttribute("aria-describedby") !== describedBy) {
      this.inputTarget.setAttribute("aria-describedby", describedBy)
    }
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
