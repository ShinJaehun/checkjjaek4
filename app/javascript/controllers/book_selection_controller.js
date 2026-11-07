import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Temporary book selection in a permanent window.
// The originating Rails form remains intact across Turbo searches.
export default class extends Controller {
  static targets = ["frame", "panel", "fields", "book"]
  static values = { maxBooks: Number }

  connect() {
    this.element.dataset.requestRevision ||= crypto.randomUUID()
    this.load()
  }

  navigate(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (!this.element.hidden && event.target.closest("[data-back-link]") && document.getElementById("book-selection-search-results")) {
      event.preventDefault()
      this.cancel()
      return
    }
    const opener = event.target.closest("[data-book-selection-open]")
    if (opener) {
      event.preventDefault()
      const composer = opener.closest("#jjaek-composer")
      this.close()
      this.composer = composer
      this.attachmentSnapshot = composer.querySelector("#jjaek-attached-books").cloneNode(true)
      this.origin = window.location.href
      composer.setAttribute("data-turbo-permanent", "")
      this.element.hidden = false
      const url = new URL(composer.dataset.selectionUrl, window.location.origin)
      for (const [field, name] of [["editingId", "editing_jjaek_id"], ["groupId", "group_id"], ["targetUserId", "target_user_id"]]) {
        if (composer.dataset[field]) url.searchParams.set(name, composer.dataset[field])
      }
      url.searchParams.set("search_origin", window.location.pathname + window.location.search)
      const returnTo = composer.querySelector("input[name='return_to']")
      if (returnTo) url.searchParams.set("return_to", returnTo.value)
      composer.querySelectorAll("input[name='selected_books[]']").forEach(input => url.searchParams.append("selected_books[]", input.value))
      this.frameTarget.src = url.href
      return
    }
    const remove = event.target.closest("[data-attachment-remove]")
    if (remove) {
      event.preventDefault()
      if (this.pendingForm) return
      const row = remove.closest("[data-book-key]")
      if (!this.element.hidden && this.hasPanelTarget) {
        const form = Array.from(this.panelTarget.querySelectorAll("form[data-book-selection-form='remove']"))
          .find(form => decodeURIComponent(new URL(form.action).pathname.split("/").pop()) === row.dataset.bookKey)
        form?.requestSubmit()
      } else row.remove()
      return
    }
    const link = event.target.closest("a[data-book-selection-navigation='true']")
    if (link && !this.element.hidden) {
      const url = new URL(link.href)
      for (const name of this.contextNames) {
        url.searchParams.delete(name)
        this.valuesFor(name).forEach(value => url.searchParams.append(name, value))
      }
      link.href = url.href
    }
  }

  get contextNames() {
    return ["selected_books[]", "group_id", "target_user_id", "editing_jjaek_id", "search_origin", "return_to", "attachment"]
  }

  prepare(event) {
    const form = event.target
    if (!form.matches("form[data-book-selection-form]")) return
    if (this.returning || this.pendingForm || !this.hasFieldsTarget) {
      event.preventDefault()
      return
    }
    this.contextNames.forEach(name => this.setFormValues(form, name, this.valuesFor(name)))
    if (form.dataset.bookSelectionForm === "search") {
      form.dataset.turboFrame = document.getElementById("book-selection-search-results") ? "book-selection-search-results" : "_top"
      form.dataset.turboAction = "advance"
    } else {
      this.pendingForm = form
      for (const name of ["query", "page"]) this.setFormValues(form, name, this.valuesFor(name))
    }
  }

  submitted(event) {
    if (event.target !== this.pendingForm) return
    const contentType = event.detail.fetchResponse?.response.headers.get("Content-Type") || ""
    // Stream rendering finishes after the response arrives. Wait for the last
    // selection Stream before allowing completion/navigation.
    if (!contentType.includes("text/vnd.turbo-stream.html")) this.pendingForm = null
  }

  beforeVisit(event) {
    if (this.element.hidden) return
    const url = new URL(event.detail.url, window.location.origin)
    if (this.returning && url.href !== this.origin) {
      this.close()
      return
    }
    this.destinationURL = url.href
    if (url.href === this.origin) {
      if (!this.returning) {
        this.restoreAttachments()
        this.returning = true
      }
    } else if (!this.selectionPage(url)) this.close()
  }

  selectionPage(url) {
    if (url.origin !== window.location.origin) return false
    const selectionSearch = url.pathname === "/book_search" && url.searchParams.get("attachment") === "1" &&
      ["editing_jjaek_id", "group_id", "target_user_id"].every(name => (url.searchParams.get(name) || "") === (this.valuesFor(name)[0] || ""))
    return selectionSearch || /^\/books\/(?:[1-9]\d*|lookup)$/.test(url.pathname)
  }

  finish() {
    if (this.returning || this.pendingForm || !this.origin) return
    this.attachmentSnapshot = null
    this.focusBodyOnReturn = true
    this.returnToComposer()
  }

  cancel() {
    if (this.returning || !this.origin) return
    this.restoreAttachments()
    this.returnToComposer()
  }

  restoreAttachments() {
    const attachments = this.composer?.querySelector("#jjaek-attached-books")
    if (attachments && this.attachmentSnapshot) attachments.replaceChildren(...this.attachmentSnapshot.childNodes)
    this.attachmentSnapshot = null
  }

  returnToComposer() {
    this.returning = true
    this.element.dataset.requestRevision = crypto.randomUUID()
    if (window.location.href === this.origin) this.completeReturn()
    else Turbo.visit(this.origin)
  }

  completeReturn() {
    const focusBody = this.focusBodyOnReturn
    const context = this.composer?.dataset
    this.close()
    if (!focusBody || !context) return

    // Resolve the live form after Turbo has restored/replaced the page DOM.
    const composer = document.getElementById("jjaek-composer")
    if (!composer || !["editingId", "groupId", "targetUserId"].every(key => composer.dataset[key] === context[key])) return
    const textarea = composer.querySelector("textarea[name='jjaek[content]']")
    if (!textarea) return
    textarea.focus({ preventScroll: true })
    requestAnimationFrame(() => {
      if (textarea.isConnected && document.activeElement === textarea) {
        textarea.scrollIntoView({ block: "center", behavior: "smooth" })
      }
    })
  }

  beforeRender(event) {
    if (this.element.hidden) return
    const url = new URL(this.returning ? this.origin : (this.destinationURL || window.location.href))
    let incoming = event.detail.newBody.querySelector("#jjaek-composer")
    if (url.href !== this.origin && this.selectionPage(url)) {
      // Keep the original draft out of the book preview's writing form.
      if (!incoming) {
        const placeholder = document.createElement("div")
        placeholder.hidden = true
        incoming = document.createElement("div")
        incoming.id = "jjaek-composer"
        placeholder.append(incoming)
        event.detail.newBody.prepend(placeholder)
      }
      const bookForm = incoming.closest("#book-jjaek-form")
      if (bookForm) bookForm.hidden = true
      incoming.setAttribute("data-turbo-permanent", "")
      return
    }
    if (url.href !== this.origin) {
      this.close()
      return
    }
    if (!this.returning) {
      this.restoreAttachments()
      this.returning = true
    }
    const current = this.composer
    const sameContext = current && incoming && ["editingId", "groupId", "targetUserId"]
      .every(key => current.dataset[key] === incoming.dataset[key])
    if (!sameContext) {
      this.close()
      return
    }
    // Turbo preserves a node only when BOTH snapshots mark its ID permanent.
    // The regular destination form must participate just for this return visit.
    const bookForm = incoming.closest("#book-jjaek-form")
    if (bookForm) bookForm.hidden = false
    incoming.setAttribute("data-turbo-permanent", "")
  }

  load(event) {
    if (this.returning && window.location.href === this.origin && !document.documentElement.hasAttribute("data-turbo-preview")) this.completeReturn()
    if (event?.type === "turbo:load") this.destinationURL = null
    const state = document.querySelector("#book-selection-search-results [data-book-selection-results-state]")
    if (state && this.hasFieldsTarget) {
      for (const name of ["query", "page"]) {
        this.fieldsTarget.querySelectorAll(`input[name='${name}']`).forEach(input => { input.value = state.dataset[name] })
      }
    }
    this.syncResults()
  }

  loaded(event) {
    if (event.target === this.frameTarget || event.target.id === "book-selection-search-results") this.load()
  }

  close() {
    this.restoreAttachments()
    this.composer?.removeAttribute("data-turbo-permanent")
    this.element.hidden = true
    this.element.dataset.requestRevision = crypto.randomUUID()
    this.frameTarget.src = null
    this.frameTarget.replaceChildren()
    this.pendingForm = null
    this.returning = false
    this.focusBodyOnReturn = false
    this.composer = null
    this.origin = null
    this.destinationURL = null
  }

  valuesFor(name) {
    if (!this.hasFieldsTarget) return []
    return Array.from(this.fieldsTarget.querySelectorAll("input")).filter(input => input.name === name).map(input => input.value)
  }

  setFormValues(form, name, values) {
    Array.from(form.querySelectorAll("input")).filter(input => input.name === name).forEach(input => input.remove())
    values.forEach(value => {
      const input = document.createElement("input")
      Object.assign(input, { type: "hidden", name, value })
      form.append(input)
    })
  }

  prepareRequest(event) {
    const target = event.target
    if (target === this.frameTarget || target.id === "book-selection-search-results" || target.matches("form[data-book-selection-form]")) {
      event.detail.fetchOptions.headers["X-Book-Selection-Revision"] = this.element.dataset.requestRevision
    }
  }

  guardResponse(event) {
    const revision = event.detail.fetchResponse.response.headers.get("X-Book-Selection-Revision")
    if (revision && revision !== this.element.dataset.requestRevision) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }

  guardStream(event) {
    if (!["book-selection-selected-books", "book-selection-fields", "book-selection-alert", "book-selection-search-results", "jjaek-attached-books"].includes(event.target.target)) return
    const revision = this.element.dataset.requestRevision
    const render = event.detail.render
    event.detail.render = async stream => {
      if (!this.element.isConnected || this.element.hidden || this.returning || this.element.dataset.requestRevision !== revision) return
      await render(stream)
      if (stream.target === "book-selection-search-results" && this.element.dataset.requestRevision === revision) {
        this.pendingForm = null
        this.syncResults()
      }
    }
  }

  guardFrame(event) {
    if (event.target !== this.frameTarget) return
    const revision = this.element.dataset.requestRevision
    const render = event.detail.render
    event.detail.render = (current, incoming) => {
      if (!this.element.isConnected || this.element.hidden || this.returning || this.element.dataset.requestRevision !== revision) return
      return render(current, incoming)
    }
  }

  syncResults() {
    const atLimit = this.valuesFor("selected_books[]").filter(Boolean).length >= this.maxBooksValue
    document.querySelectorAll("[data-book-selection-result]").forEach(result => {
      const selected = this.bookTargets.some(book => ["bookId", "isbn", "url"].some(key => result.dataset[key] && result.dataset[key] === book.dataset[key]))
      result.querySelector("[data-book-selection-selected]").hidden = !selected
      result.querySelector("[data-book-selection-add]").hidden = selected
      result.querySelector("input[type='submit']").disabled = atLimit
    })
  }
}
