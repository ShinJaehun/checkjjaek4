import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["location", "personal", "group", "groupSelect", "groupMessage", "visibility", "submit"]
  static values = { personalLabel: String, groupLabel: String, groupPrompt: String, noGroups: String }

  connect() {
    this.change()
  }

  change() {
    const groupPost = this.locationTargets.some(input => input.checked && input.value === "group")
    const label = groupPost ? this.groupLabelValue : this.personalLabelValue
    this.personalTarget.hidden = groupPost
    this.visibilityTargets.forEach(input => { input.disabled = groupPost })
    this.groupTarget.hidden = !groupPost
    this.groupSelectTarget.disabled = !groupPost
    this.groupSelectTarget.required = groupPost
    this.submitTarget.value = label
    this.submitTarget.disabled = groupPost && !this.groupSelectTarget.value

    const selectedOption = this.groupSelectTarget.selectedOptions[0]
    const hasGroups = this.groupSelectTarget.options.length > 1
    this.groupMessageTarget.textContent = selectedOption?.dataset.destinationMessage ||
      (hasGroups ? this.groupPromptValue : this.noGroupsValue)
  }
}
