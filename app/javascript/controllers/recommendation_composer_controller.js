import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["frame", "panel", "fields", "selection", "writing", "title", "continue", "book", "completed"]
  static values = { selectionTitle: String, writingTitle: String, maxBooks: Number }

  connect() {
    this.load()
  }

  panelTargetConnected() {
    this.sync()
  }

  fieldsTargetConnected() {
    this.sync()
  }

  completedTargetConnected(element) {
    const destination = new URL(element.dataset.location, window.location.origin)
    if (destination.origin !== window.location.origin) return
    this.close()
    Turbo.visit(destination.href)
  }

  navigate(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const menu = event.target.closest("a, button[aria-controls='global-book-search-dialog']")
    if (menu?.closest("[data-recommendation-navigation-end]") && !menu.closest("dialog")) {
      this.close()
      return
    }
    const opener = event.target.closest("a[data-recommendation-open]")
    if (opener) {
      event.preventDefault()
      if (!this.hasPanelTarget || this.panelTarget.dataset.groupId !== (opener.dataset.recommendationGroupId || "")) {
        this.close()
        this.frameTarget.src = opener.href
      }
      this.element.hidden = false
      return
    }

    const link = event.target.closest("a[data-recommendation-navigation='true']")
    if (!link) return
    const url = new URL(link.href)
    url.searchParams.delete("selected_books[]")
    this.valuesFor("selected_books[]").forEach(value => url.searchParams.append("selected_books[]", value))
    if (this.hasFieldsTarget) {
      for (const name of ["group_id", "search_origin"]) {
        url.searchParams.delete(name)
        this.valuesFor(name).forEach(value => url.searchParams.append(name, value))
      }
    }
    link.href = url.toString()
  }

  close() {
    this.element.hidden = true
    this.element.dataset.revision = String(Number(this.element.dataset.revision || 0) + 1)
    this.frameTarget.src = null
    this.frameTarget.replaceChildren()
    this.titleTarget.textContent = this.selectionTitleValue
    document.querySelectorAll("[data-recommendation-reset]").forEach(element => element.remove())
    document.querySelectorAll("form[data-recommendation-selection-form] input").forEach(input => {
      if (["selected_books[]", "search_origin"].includes(input.name)) input.remove()
    })
    this.syncResults()
  }

  write() {
    if (!this.valuesFor("selected_books[]").length) return
    this.setStep("writing")
    this.writingTarget.querySelector("textarea").focus()
  }

  select() {
    this.setStep("selection")
    this.panelTarget.querySelector("#recommendation-query").focus()
  }

  setStep(step) {
    if (!this.hasPanelTarget) return
    this.panelTarget.dataset.step = step
    this.selectionTargets.forEach(element => { element.hidden = step === "writing" })
    this.writingTargets.forEach(element => { element.hidden = step !== "writing" })
    this.titleTarget.textContent = step === "writing" ? this.writingTitleValue : this.selectionTitleValue
  }

  valuesFor(name) {
    if (!this.hasFieldsTarget) return []
    return Array.from(this.fieldsTarget.querySelectorAll("input")).filter(input => input.name === name).map(input => input.value)
  }

  prepare(event) {
    const form = event.target
    if (form.closest("[data-recommendation-navigation-end]") && !form.closest("dialog")) {
      this.close()
      return
    }
    if (form.id === "recommendation-jjaek-form" || !form.matches("form[data-recommendation-selection-form]")) return

    this.element.hidden = false
    if (!this.hasFieldsTarget) {
      form.querySelectorAll("input[name='selected_books[]']").forEach(input => input.remove())
      form.querySelectorAll("input[name='search_origin']").forEach(input => input.remove())
      this.setFormValues(form, "start_recommendation", ["1"])
      return
    }
    form.querySelectorAll("input[name='start_recommendation']").forEach(input => input.remove())
    const names = ["selected_books[]", "group_id", "search_origin"]
    if (form.dataset.recommendationSelectionForm === "search") {
      const results = document.getElementById("recommendation-search-results")
      const state = results?.querySelector("[data-recommendation-results-state]")
      const sameGroup = state && (state.dataset.groupId || "") === (this.panelTarget.dataset.groupId || "")
      form.dataset.turboFrame = sameGroup ? results.id : "_top"
      form.dataset.turboAction = "advance"
    } else {
      if (form.dataset.recommendationSelectionForm !== "add") names.push("query", "page")
    }
    names.forEach(name => { this.setFormValues(form, name, this.valuesFor(name)) })
  }

  setFormValues(form, name, values) {
    Array.from(form.querySelectorAll("input")).filter(input => input.name === name).forEach(input => input.remove())
    values.forEach(value => {
      const input = document.createElement("input")
      Object.assign(input, { type: "hidden", name, value })
      form.append(input)
    })
  }

  guardStream(event) {
    const targets = ["recommendation_composer", "recommendation-selected-books", "recommendation-selection-fields", "recommendation-selection-alert", "recommendation-search-results"]
    if (!targets.includes(event.target.target)) return
    const panel = this.hasPanelTarget ? this.panelTarget : null
    const revision = this.element.dataset.revision
    const render = event.detail.render
    event.detail.render = stream => {
      if (!this.element.isConnected || this.element.hidden || this.element.dataset.revision !== revision) return
      if (panel && (!this.hasPanelTarget || this.panelTarget !== panel)) return
      return render(stream)
    }
  }

  guardFrame(event) {
    if (event.target !== this.frameTarget) return
    const revision = this.element.dataset.revision
    const render = event.detail.render
    event.detail.render = (current, incoming) => {
      if (!this.element.isConnected || this.element.hidden || this.element.dataset.revision !== revision) return
      return render(current, incoming)
    }
  }

  loaded(event) {
    if (event.target.id === "recommendation-search-results") this.load()
  }

  load() {
    if (!this.hasPanelTarget) {
      document.querySelectorAll("[data-recommendation-reset]").forEach(element => element.remove())
      this.syncResults()
      return
    }
    const reset = document.querySelector("[data-recommendation-reset]")
    if (reset) {
      for (const id of ["recommendation-selected-books", "recommendation-selection-fields", "recommendation-selection-alert"]) {
        const incoming = reset.content.querySelector(`#${id}`)
        if (incoming) this.panelTarget.querySelector(`#${id}`).replaceWith(incoming.cloneNode(true))
      }
      reset.remove()
    }
    const state = document.querySelector("#recommendation-search-results [data-recommendation-results-state]")
    if (state && (state.dataset.groupId || "") === (this.panelTarget.dataset.groupId || "")) {
      for (const name of ["query", "page"]) {
        const input = this.fieldsTarget.querySelector(`input[name='${name}']`)
        if (input) input.value = state.dataset[name]
      }
    }
    this.sync()
  }

  sync() {
    if (this.hasPanelTarget && this.hasFieldsTarget) {
      this.setStep(this.panelTarget.dataset.step)
      this.continueTarget.disabled = !this.valuesFor("selected_books[]").length
    }
    this.syncResults()
  }

  syncResults() {
    const atLimit = this.valuesFor("selected_books[]").length >= this.maxBooksValue
    document.querySelectorAll("[data-recommendation-result]").forEach(result => {
      const selected = this.bookTargets.some(book => ["bookId", "isbn", "url"].some(key => result.dataset[key] && result.dataset[key] === book.dataset[key]))
      result.querySelector("[data-recommendation-selected]").hidden = !selected
      result.querySelector("[data-recommendation-add]").hidden = selected
      result.querySelector("input[type='submit']").disabled = atLimit
    })
  }
}
