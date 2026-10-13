import { readFile } from "node:fs/promises"
import test from "node:test"
import assert from "node:assert/strict"

// Load the application's controller with only its Stimulus base class stubbed.
// The behavior below needs targets, not a browser or the importmap runtime.
const source = await readFile(new URL("../../app/javascript/controllers/content_length_controller.js", import.meta.url), "utf8")
const { default: ContentLengthController } = await import(`data:text/javascript,${encodeURIComponent(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}"))}`)

function controller(value, serverError = "") {
  const instance = new ContentLengthController()
  const classes = new Set()
  instance.limitValue = 200
  instance.messageValue = "내용은 200자 이하로 입력해 주세요."
  instance.inputTarget = {
    value,
    validity: { customError: false },
    setCustomValidity(message) {
      this.validationMessage = message
      this.validity.customError = message !== ""
    },
    focus() { this.focused = true }
  }
  instance.counterTarget = {
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) } }
  }
  instance.errorsTarget = {}
  instance.serverErrorsTarget = { textContent: serverError }
  instance.warningTarget = {}
  instance.connect()
  return { instance, classes }
}

test("0 and 200 characters are neutral; 201 shows the warning and blocks submission; recovery clears it", () => {
  const { instance, classes } = controller("")
  for (const count of [0, 200, 201, 200, 0]) {
    instance.inputTarget.value = "한".repeat(count)
    instance.update()
    const overLimit = count > 200
    assert.equal(instance.counterTarget.textContent, `${count} / 200`)
    assert.equal(classes.has("text-red-700"), overLimit)
    assert.equal(classes.has("text-stone-400"), !overLimit)
    assert.equal(instance.warningTarget.hidden, !overLimit)
    assert.equal(instance.errorsTarget.hidden, !overLimit)
    assert.equal(instance.inputTarget.validity.customError, overLimit)
    assert.equal(instance.inputTarget.value.length, count)
  }
})

test("emoji and normalized line breaks keep the existing code point count", () => {
  const { instance } = controller("🙂".repeat(198) + "\r\n!")
  assert.equal(instance.counterTarget.textContent, "200 / 200")
  assert.equal(instance.warningTarget.hidden, true)
  instance.inputTarget.value += "\r"
  instance.update()
  assert.equal(instance.counterTarget.textContent, "201 / 200")
  assert.equal(instance.warningTarget.hidden, false)
})

test("reconnecting uses the same warning, and clearing overflow preserves other server errors", () => {
  const { instance } = controller("a".repeat(201), "내용을 입력해 주세요.")
  const warning = instance.warningTarget
  instance.connect()
  assert.equal(instance.warningTarget, warning)
  instance.inputTarget.value = "a"
  instance.update()
  assert.equal(instance.warningTarget.hidden, true)
  assert.equal(instance.errorsTarget.hidden, false)
  assert.equal(instance.serverErrorsTarget.textContent, "내용을 입력해 주세요.")
})

test("overflow uses the inline error instead of a duplicate native validation popup", () => {
  const { instance } = controller("a".repeat(201))
  let prevented = false
  instance.invalid({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(instance.inputTarget.focused, true)
  assert.equal(instance.inputTarget.validationMessage, "내용은 200자 이하로 입력해 주세요.")
})
