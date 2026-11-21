// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "trix"
import "controllers"

// Old library links selected notes with a fragment before there was a separate tab.
function followLibraryNotesAnchor() {
  if (window.location.hash !== "#book-notes") return

  const notesLink = document.querySelector("[data-library-notes-link]:not([aria-current='page'])")
  if (notesLink) Turbo.visit(notesLink.href, { action: "replace" })
}

document.addEventListener("turbo:load", followLibraryNotesAnchor)
window.addEventListener("hashchange", followLibraryNotesAnchor)
