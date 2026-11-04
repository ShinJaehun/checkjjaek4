import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["frame", "panel", "fields", "selection", "writing", "title", "continue", "book", "completed"]
  static values = { selectionTitle: String, writingTitle: String, editingTitle: String, maxBooks: Number }

  connect() {
    this.element.dataset.requestRevision ||= crypto.randomUUID()
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
    const editing = this.hasPanelTarget && this.panelTarget.dataset.mode === "edit"
    const editOpener = event.target.closest("a[data-recommendation-edit-open='true']")
    if (editOpener) {
      event.preventDefault()
      this.close()
      this.frameTarget.src = editOpener.href
      this.element.hidden = false
      return
    }
    const anchor = event.target.closest("a")
    if (editing && anchor?.matches("[data-back-link]") && this.editSearchVisible()) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.cancel()
      return
    }
    const menu = event.target.closest("a, button[aria-controls='global-book-search-dialog']")
    if (menu?.closest("[data-recommendation-navigation-end]") && !menu.closest("dialog")) {
      this.close()
      return
    }
    const opener = event.target.closest("a[data-recommendation-open]")
    if (opener) {
      event.preventDefault()
      if (!this.hasPanelTarget || this.panelTarget.dataset.mode === "edit" || this.panelTarget.dataset.groupId !== (opener.dataset.recommendationGroupId || "")) {
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
    for (const name of ["group_id", "search_origin", "editing_jjaek_id", "return_to"]) {
      url.searchParams.delete(name)
      this.valuesFor(name).forEach(value => url.searchParams.append(name, value))
    }
    link.href = url.toString()
  }

  beforeVisit(event) {
    if (!this.hasPanelTarget || this.panelTarget.dataset.mode !== "edit") return
    const destination = new URL(event.detail.url, window.location.origin)
    const form = this.panelTarget.querySelector("form[data-recommendation-selection-form='search']")
    const search = new URL(form.action)
    this.preserveEditOnVisit = destination.origin === search.origin && destination.pathname === search.pathname &&
      destination.searchParams.get("editing_jjaek_id") === this.panelTarget.dataset.editingId
    if (!this.preserveEditOnVisit) this.close()
  }

  beforeCache() {
    if (this.hasPanelTarget && this.panelTarget.dataset.mode === "edit" && !this.preserveEditOnVisit) this.close()
  }

  beforeRender(event) {
    if (!this.hasPanelTarget || this.panelTarget.dataset.mode !== "edit") return
    const state = event.detail.newBody.querySelector("[data-recommendation-results-state]")
    if (state?.dataset.editingId !== this.panelTarget.dataset.editingId) this.close()
  }

  editSearchVisible() {
    if (!this.hasPanelTarget || this.panelTarget.dataset.mode !== "edit") return false
    const state = document.querySelector("#recommendation-search-results [data-recommendation-results-state]")
    return state?.dataset.editingId === this.panelTarget.dataset.editingId
  }

  cancel() {
    const destination = this.editSearchVisible() ? this.panelTarget.dataset.returnPath : null
    this.close()
    if (destination) {
      const url = new URL(destination, window.location.origin)
      if (url.origin === window.location.origin) Turbo.visit(url.href)
    }
  }

  close() {
    const editing = this.hasPanelTarget && this.panelTarget.dataset.mode === "edit"
    this.element.hidden = true
    this.element.dataset.requestRevision = crypto.randomUUID()
    this.pendingForm = null
    this.preserveEditOnVisit = false
    this.element.dataset.revision = String(Number(this.element.dataset.revision || 0) + 1)
    this.frameTarget.src = null
    this.frameTarget.replaceChildren()
    this.titleTarget.textContent = this.selectionTitleValue
    document.querySelectorAll("[data-recommendation-reset]").forEach(element => element.remove())
    document.querySelectorAll("form[data-recommendation-selection-form] input").forEach(input => {
      const resetNames = ["selected_books[]", "search_origin", "editing_jjaek_id", "return_to"]
      if (editing) resetNames.push("query", "page", "group_id")
      if (resetNames.includes(input.name)) input.remove()
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
    if (this.panelTarget.dataset.mode === "edit") step = "writing"
    this.panelTarget.dataset.step = step
    this.selectionTargets.forEach(element => { element.hidden = step === "writing" })
    this.writingTargets.forEach(element => { element.hidden = step !== "writing" })
    this.titleTarget.textContent = this.panelTarget.dataset.mode === "edit" ? this.editingTitleValue :
      (step === "writing" ? this.writingTitleValue : this.selectionTitleValue)
  }

  valuesFor(name) {
    if (!this.hasFieldsTarget) return []
    return Array.from(this.fieldsTarget.querySelectorAll("input")).filter(input => input.name === name).map(input => input.value).filter(value => name !== "selected_books[]" || value !== "")
  }

  prepare(event) {
    const form = event.target
    if (form.closest("[data-recommendation-navigation-end]") && !form.closest("dialog")) {
      this.close()
      return
    }
    const selectionForm = form.matches("form[data-recommendation-selection-form]")
    const publishForm = form.id === "recommendation-jjaek-form"
    if (!selectionForm && !publishForm) return
    if (this.pendingForm) {
      event.preventDefault()
      return
    }
    if (form.method.toLowerCase() !== "get") this.pendingForm = form
    if (publishForm) return

    this.element.hidden = false
    if (!this.hasFieldsTarget) {
      form.querySelectorAll("input[name='selected_books[]']").forEach(input => input.remove())
      form.querySelectorAll("input[name='search_origin']").forEach(input => input.remove())
      this.setFormValues(form, "start_recommendation", ["1"])
      return
    }
    form.querySelectorAll("input[name='start_recommendation']").forEach(input => input.remove())
    const names = ["selected_books[]", "group_id", "search_origin", "editing_jjaek_id", "return_to"]
    if (form.dataset.recommendationSelectionForm === "search") {
      const results = document.getElementById("recommendation-search-results")
      const state = results?.querySelector("[data-recommendation-results-state]")
      const sameGroup = state && (state.dataset.groupId || "") === (this.panelTarget.dataset.groupId || "") &&
        (state.dataset.editingId || "") === (this.panelTarget.dataset.editingId || "")
      form.dataset.turboFrame = sameGroup ? results.id : "_top"
      form.dataset.turboAction = "advance"
    } else {
      if (form.dataset.recommendationSelectionForm !== "add") names.push("query", "page")
    }
    names.forEach(name => { this.setFormValues(form, name, this.valuesFor(name)) })
  }

  submitted(event) {
    if (event.target === this.pendingForm) this.pendingForm = null
  }

  prepareRequest(event) {
    const target = event.target
    if (target === this.frameTarget || target.id === "recommendation-search-results" ||
        target.id === "recommendation-jjaek-form" || target.matches("form[data-recommendation-selection-form]")) {
      event.detail.fetchOptions.headers["X-Recommendation-Revision"] = this.element.dataset.requestRevision
    }
  }

  guardResponse(event) {
    const revision = event.detail.fetchResponse.response.headers.get("X-Recommendation-Revision")
    if (revision && revision !== this.element.dataset.requestRevision) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
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
    this.preserveEditOnVisit = false
    const editStart = document.querySelector("[data-recommendation-edit-start]")
    if (editStart) {
      this.close()
      this.frameTarget.append(editStart.content.cloneNode(true))
      editStart.remove()
      this.element.hidden = false
    }
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
    if (state && (state.dataset.groupId || "") === (this.panelTarget.dataset.groupId || "") &&
        (state.dataset.editingId || "") === (this.panelTarget.dataset.editingId || "")) {
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
