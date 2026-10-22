import { readFile } from "node:fs/promises"
import test, { afterEach } from "node:test"
import assert from "node:assert/strict"

// Exercise the real controller with only Stimulus targets and browser APIs stubbed.
const source = await readFile(new URL("../../app/javascript/controllers/group_carousel_controller.js", import.meta.url), "utf8")
const { default: GroupCarouselController } = await import(`data:text/javascript,${encodeURIComponent(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}"))}`)
const originalWindow = globalThis.window
const originalDocument = globalThis.document

afterEach(() => {
  globalThis.window = originalWindow
  globalThis.document = originalDocument
})

function carousel(count, width) {
  const queries = [1024, 768].map(minimum => ({
    minimum,
    matches: width >= minimum,
    listeners: new Set(),
    addEventListener(_event, callback) { this.listeners.add(callback) },
    removeEventListener(_event, callback) { this.listeners.delete(callback) }
  }))
  globalThis.window = { matchMedia: query => queries.find(item => query.includes(String(item.minimum))) }
  globalThis.document = { activeElement: null }
  const instance = new GroupCarouselController()
  instance.cardTargets = Array.from({ length: count }, (_, id) => ({
    id,
    link: { id },
    contains(element) { return element === this || element === this.link }
  }))
  instance.viewportTarget = { focus() { document.activeElement = this } }
  instance.previousTarget = {}
  instance.nextTarget = {}
  instance.positionTarget = {}
  instance.controlsTarget = {
    contains(element) { return element === instance.previousTarget || element === instance.nextTarget }
  }
  instance.connect()

  return {
    instance,
    queries,
    resize(nextWidth) {
      const changed = queries.filter(query => query.matches !== (nextWidth >= query.minimum))
      queries.forEach(query => { query.matches = nextWidth >= query.minimum })
      changed.forEach(query => query.listeners.forEach(callback => callback()))
    }
  }
}

function visibleIds(instance) {
  return instance.cardTargets.filter(card => !card.hidden).map(card => card.id)
}

for (const [width, pageSize] of [[390, 1], [900, 2], [1280, 3]]) {
  test(`${width}px shows ${pageSize} cards per page and visits every card in order`, () => {
    const { instance } = carousel(7, width)
    const pageCount = Math.ceil(7 / pageSize)
    assert.equal(instance.controlsTarget.hidden, false)
    assert.equal(instance.previousTarget.disabled, true)
    const visited = []
    for (let index = 0; index < pageCount; index++) {
      assert.equal(instance.positionTarget.textContent, `${index + 1} / ${pageCount}`)
      assert.deepEqual(visibleIds(instance), Array.from({ length: 7 }, (_, id) => id).slice(index * pageSize, (index + 1) * pageSize))
      visited.push(...visibleIds(instance))
      instance.next()
    }
    assert.deepEqual(visited, [0, 1, 2, 3, 4, 5, 6])
    assert.equal(instance.index, pageCount - 1)
    assert.equal(instance.nextTarget.disabled, true)

    const key = value => instance.navigate({ key: value, target: instance.viewportTarget, preventDefault() {} })
    key("Home")
    instance.previous()
    assert.equal(instance.index, 0)
    key("ArrowRight")
    assert.equal(instance.index, 1)
    key("ArrowLeft")
    assert.equal(instance.index, 0)
    key("End")
    assert.equal(instance.index, pageCount - 1)
  })
}

test("resizing preserves the focused card, complete order, and reachable last pages", () => {
  for (const count of [2, 3, 4, 7]) {
    const { instance, resize, queries } = carousel(count, 390)
    instance.showPage(count - 1)
    const focusedLink = instance.cardTargets[count - 1].link
    document.activeElement = focusedLink
    for (const [width, pageSize] of [[900, 2], [1280, 3], [390, 1]]) {
      resize(width)
      assert.ok(visibleIds(instance).includes(count - 1))
      assert.equal(instance.pageCount, Math.ceil(count / pageSize))
      assert.equal(instance.controlsTarget.hidden, count <= pageSize)
      assert.equal(document.activeElement, focusedLink)
      assert.deepEqual(instance.cardTargets.map(card => card.id), Array.from({ length: count }, (_, id) => id))
    }
    instance.showPage(0)
    assert.equal(document.activeElement, instance.viewportTarget)
    instance.disconnect()
    assert.ok(queries.every(query => query.listeners.size === 0))
  }
})

test("shrinking the number of pages moves focus out of navigation controls before hiding them", () => {
  const { instance, resize } = carousel(3, 390)
  document.activeElement = instance.nextTarget
  resize(1280)
  assert.deepEqual(visibleIds(instance), [0, 1, 2])
  assert.equal(instance.controlsTarget.hidden, true)
  assert.equal(instance.previousTarget.disabled, true)
  assert.equal(instance.nextTarget.disabled, true)
  assert.equal(document.activeElement, instance.viewportTarget)
})
