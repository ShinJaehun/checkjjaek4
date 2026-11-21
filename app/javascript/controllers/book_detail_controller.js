import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["tab", "composer", "composerToggle"]

  connect() {
    if (this.hasComposerTarget) {
      const open = !this.composerTarget.hidden
      this.setComposerExpanded(open)
      if (open) {
        // The existing book selector also opens the composer when it restores a draft.
        const tab = this.tabTargets.find(tab => this.panelFor(tab).contains(this.composerTarget))
        if (tab) this.showTab(tab)
        return
      }
    }
    this.revealAnchor()
  }

  selectTab(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return

    event.preventDefault()
    this.activateTab(event.currentTarget)
    event.currentTarget.focus({ preventScroll: true })
  }

  navigateTabs(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.target)
    if (index < 0) return

    let next
    switch (event.key) {
      case "ArrowLeft":
        next = tabs[(index + tabs.length - 1) % tabs.length]
        break
      case "ArrowRight":
        next = tabs[(index + 1) % tabs.length]
        break
      case "Home":
        next = tabs[0]
        break
      case "End":
        next = tabs[tabs.length - 1]
        break
      case " ":
        next = tabs[index]
        break
      default:
        return
    }

    event.preventDefault()
    this.activateTab(next)
    next.focus()
  }

  toggleComposer() {
    this.setComposerExpanded(this.composerTarget.hidden)
  }

  revealAnchor() {
    const target = document.getElementById(window.location.hash.slice(1))
    if (!target || !this.element.contains(target)) return

    const tab = this.tabTargets.find(tab => this.panelFor(tab).contains(target))
    if (tab) this.showTab(tab)
    if (this.hasComposerTarget && this.composerTarget.contains(target)) this.setComposerExpanded(true)
    requestAnimationFrame(() => target.scrollIntoView({ block: "start" }))
  }

  activateTab(tab) {
    this.showTab(tab)
    // Keep the current Turbo history entry in sync while retaining the form DOM.
    const history = Turbo.navigator.history
    history.replace(new URL(tab.href), history.restorationIdentifier)
  }

  showTab(selectedTab) {
    this.tabTargets.forEach(tab => {
      const selected = tab === selectedTab
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
      this.panelFor(tab).hidden = !selected
    })
  }

  panelFor(tab) {
    return document.getElementById(tab.getAttribute("aria-controls"))
  }

  setComposerExpanded(expanded) {
    this.composerTarget.hidden = !expanded
    this.composerToggleTarget.setAttribute("aria-expanded", String(expanded))
  }
}
