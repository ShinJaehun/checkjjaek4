import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { message: String }

  checkResponse(event) {
    if (!event.detail.fetchResponse.succeeded) this.recover(event)
  }

  recover(event) {
    event.preventDefault()
    window.alert(this.messageValue)
    window.location.reload()
  }
}
