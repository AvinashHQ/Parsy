import { Controller } from "@hotwired/stimulus"

// Links a finding/field to its evidence row: scrolls the target into view and
// briefly flashes it. Used from finding chips (click) and editor fields (focus).
export default class extends Controller {
  highlight(event) {
    const id = event.params.id
    if (!id) return
    if (event.type === "click") event.preventDefault()

    const el = document.getElementById(id)
    if (!el) return

    el.scrollIntoView({ behavior: "smooth", block: "center" })
    el.classList.remove("evidence-flash")
    void el.offsetWidth
    el.classList.add("evidence-flash")

    window.clearTimeout(this._timer)
    this._timer = window.setTimeout(() => el.classList.remove("evidence-flash"), 1800)
  }
}
