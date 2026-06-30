import { Controller } from "@hotwired/stimulus"

// Toggles the `.dark` class on <html> and persists the choice to localStorage.
// The initial theme is applied by an inline <head> script (no-FOUC); this
// controller only handles explicit user toggles after load.
export default class extends Controller {
  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")
    try {
      localStorage.setItem("theme", isDark ? "dark" : "light")
    } catch (e) {}
  }
}
