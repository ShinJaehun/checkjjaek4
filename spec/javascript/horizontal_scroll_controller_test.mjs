import { readFile } from "node:fs/promises"
import test, { afterEach } from "node:test"
import assert from "node:assert/strict"

const source = await readFile(new URL("../../app/javascript/controllers/horizontal_scroll_controller.js", import.meta.url), "utf8")
const { default: HorizontalScrollController } = await import(`data:text/javascript,${encodeURIComponent(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}"))}`)
const originalGlobals = Object.fromEntries(
  ["ResizeObserver", "MutationObserver", "requestAnimationFrame", "cancelAnimationFrame"].map(name => [name, globalThis[name]])
)

afterEach(() => {
  Object.assign(globalThis, originalGlobals)
})

function controller(width, contentWidth) {
  const instance = new HorizontalScrollController()
  const button = () => {
    const classes = new Set(["hidden"])
    return { classes, classList: { toggle(name, hidden) { hidden ? classes.add(name) : classes.delete(name) } } }
  }
  instance.element = { clientWidth: width }
  instance.previousTarget = button()
  instance.nextTarget = button()
  instance.hasScrollerTarget = true
  instance.hasSelectedTarget = false
  instance.scrollerTarget = {
    contentWidth,
    scrollLeft: 0,
    get clientWidth() {
      return instance.element.clientWidth - (instance.previousTarget.classes.has("hidden") ? 0 : 48)
    },
    get scrollWidth() { return Math.max(this.contentWidth, this.clientWidth) },
    scrollTo({ left }) { this.scrollLeft = Math.max(0, Math.min(left, this.scrollWidth - this.clientWidth)) },
    scrollBy({ left }) { this.scrollTo({ left: this.scrollLeft + left }) }
  }
  return instance
}

test("fitting tabs leave no controls, including after resizing or removing tabs", () => {
  const instance = controller(600, 590)
  instance.layout()
  assert.equal(instance.previousTarget.classes.has("hidden"), true)
  assert.equal(instance.nextTarget.classes.has("hidden"), true)
  assert.equal(instance.scrollerTarget.clientWidth, 600)

  instance.element.clientWidth = 500
  instance.layout()
  assert.equal(instance.nextTarget.classes.has("hidden"), false)
  instance.element.clientWidth = 600
  instance.layout()
  assert.equal(instance.nextTarget.classes.has("hidden"), true)

  instance.scrollerTarget.contentWidth = 900
  instance.layout()
  assert.equal(instance.nextTarget.classes.has("hidden"), false)
  instance.scrollerTarget.contentWidth = 580
  instance.layout()
  assert.equal(instance.nextTarget.classes.has("hidden"), true)
  assert.equal(instance.scrollerTarget.clientWidth, 600)
})

test("overflowing tabs disable each boundary and keep the selected tab visible", () => {
  const instance = controller(600, 1200)
  instance.layout()
  assert.equal(instance.previousTarget.disabled, true)
  assert.equal(instance.nextTarget.disabled, false)
  instance.scrollRight()
  instance.updateControls()
  assert.equal(instance.scrollerTarget.scrollLeft, 280)
  assert.equal(instance.previousTarget.disabled, false)
  assert.equal(instance.nextTarget.disabled, false)
  instance.scrollRight()
  instance.scrollRight()
  instance.updateControls()
  assert.equal(instance.nextTarget.disabled, true)
  instance.scrollLeft()
  instance.updateControls()
  assert.equal(instance.nextTarget.disabled, false)

  instance.hasSelectedTarget = true
  instance.selectedTarget = { offsetLeft: 1000, clientWidth: 150 }
  instance.layout()
  assert.ok(instance.scrollerTarget.scrollLeft <= instance.selectedTarget.offsetLeft)
  assert.ok(instance.scrollerTarget.scrollLeft + instance.scrollerTarget.clientWidth >= 1150)
})

test("reconnecting observes the new layout and disconnecting cleans up observers and pending work", () => {
  class Observer {
    constructor(callback) { this.callback = callback }
    observe(target) { this.target = target }
    disconnect() { this.disconnected = true }
  }
  globalThis.ResizeObserver = Observer
  globalThis.MutationObserver = Observer
  let frame
  globalThis.requestAnimationFrame = callback => { frame = callback; return 1 }
  let cancelled
  globalThis.cancelAnimationFrame = id => { cancelled = id }
  const instance = controller(600, 500)
  instance.connect()
  frame()
  instance.scrollerTarget.contentWidth = 1200
  instance.mutationObserver.callback()
  assert.equal(instance.nextTarget.classes.has("hidden"), false)
  instance.element.clientWidth = 1300
  instance.resizeObserver.callback()
  assert.equal(instance.nextTarget.classes.has("hidden"), true)
  const observers = [instance.resizeObserver, instance.mutationObserver]
  instance.disconnect()
  assert.ok(observers.every(observer => observer.disconnected))
  assert.equal(cancelled, 1)

  instance.element.clientWidth = 600
  instance.connect()
  frame()
  assert.equal(instance.nextTarget.classes.has("hidden"), false)
  assert.equal(instance.previousTarget.disabled, true)
  assert.equal(instance.resizeObserver.target, instance.scrollerTarget)
  assert.equal(instance.mutationObserver.target, instance.scrollerTarget)
  instance.disconnect()
})
