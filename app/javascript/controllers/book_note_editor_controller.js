import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["dialog", "opener", "title", "editor", "picker", "save", "attachmentError", "uploadStatus"]
  static values = { discardMessage: String, discardPath: String, uploadUrl: String, maxSize: Number, imageLimit: Number, imageAlt: String, errors: Object }

  connect() {
    this.uploads = new Map()
    if (this.hasDiscardPathValue) this.open()
  }

  disconnect() {
    this.abortUploads()
  }

  open() {
    if (this.dialogTarget.open) return

    this.initialTitle = this.titleTarget.value
    this.initialBody = this.editorTarget.value
    this.attachmentErrorTarget.hidden = true
    this.dialogTarget.showModal()
  }

  close(event) {
    event.preventDefault()
    const changed = this.hasDiscardPathValue || this.uploads.size > 0 ||
      this.titleTarget.value !== this.initialTitle ||
      this.bodySnapshot(this.editorTarget.value) !== this.bodySnapshot(this.initialBody)
    if (changed && !window.confirm(this.discardMessageValue)) return

    this.abortUploads()
    this.updateUploadState()
    this.dialogTarget.close()
    this.openerTarget.focus()

    if (this.hasDiscardPathValue) {
      Turbo.visit(this.discardPathValue, { action: "replace" })
    } else if (changed) {
      this.titleTarget.value = this.initialTitle
      this.editorTarget.value = this.initialBody
    }
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close(event)
  }

  rememberSelection() {
    this.pickerRange = this.editorTarget.editor.getSelectedRange()
  }

  chooseImages(event) {
    if (event.detail === 0) this.rememberSelection()
    this.attachmentErrorTarget.hidden = true
    this.pickerTarget.click()
  }

  insertImages() {
    const editor = this.editorTarget.editor
    const files = Array.from(this.pickerTarget.files)
    this.pickerTarget.value = ""
    this.editorTarget.focus()
    if (this.pickerRange) editor.setSelectedRange(this.pickerRange)
    this.pickerRange = null
    editor.recordUndoEntry("Insert Images")
    editor.insertFiles(files)
  }

  pasteFiles(event) {
    const files = event.clipboardData?.files
    if (!files?.length || !this.editorTarget.contains(event.target)) return

    event.preventDefault()
    event.stopPropagation()
    const editor = this.editorTarget.editor
    editor.recordUndoEntry("Paste Images")
    editor.insertFiles(files)
  }

  acceptFile(event) {
    const file = event.file
    const extensionAllowed = !file.type && /\.(jpe?g|png|webp)$/i.test(file.name)
    let error
    if (file.size > this.maxSizeValue) error = "too_large"
    else if (!file.size) error = "invalid_image"
    else if (!extensionAllowed && !this.pickerTarget.accept.split(",").includes(file.type)) error = "unsupported_format"
    if (!error) return

    event.preventDefault()
    this.showError(error)
  }

  addAttachment({ attachment }) {
    if (this.isLocalImage(attachment.getAttributes())) return

    const file = attachment.getFile()
    if (!file) {
      this.rejectAttachment(attachment, "attachments_not_allowed")
      return
    }

    const savedCount = this.editorTarget.editor.getDocument().getAttachments()
      .filter(image => this.isLocalImage(image.getAttributes())).length
    if (savedCount + this.uploads.size >= this.imageLimitValue) {
      this.rejectAttachment(attachment, "image_limit")
      return
    }

    const request = new XMLHttpRequest()
    this.uploads.set(attachment.id, request)
    this.updateUploadState()
    request.open("POST", this.uploadUrlValue)
    request.responseType = "json"
    request.timeout = 120000
    request.setRequestHeader("Accept", "application/json")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) request.setRequestHeader("X-CSRF-Token", token)
    request.upload.onprogress = (event) => {
      if (event.lengthComputable) attachment.setUploadProgress(event.loaded / event.total * 100)
    }
    request.onload = () => this.finishUpload(attachment, request)
    request.onerror = request.ontimeout = () => this.finishUpload(attachment, request)
    const data = new FormData()
    data.append("image", file)
    request.send(data)
  }

  finishUpload(attachment, request) {
    if (this.uploads.get(attachment.id) !== request) return

    this.uploads.delete(attachment.id)
    const image = request.response
    const attributes = { bookNoteImageId: image?.id, url: image?.url, contentType: "image/webp" }
    if (request.status === 201 && this.isLocalImage(attributes)) {
      attachment.setAttributes({ ...attributes, alt: this.imageAltValue, filename: "", filesize: null })
    } else {
      this.rejectAttachment(attachment, image?.error || "upload_failed", image?.message)
    }
    this.updateUploadState()
  }

  removeAttachment({ attachment }) {
    const request = this.uploads.get(attachment.id)
    if (!request) return

    this.uploads.delete(attachment.id)
    request.abort()
    this.updateUploadState()
  }

  guardSubmit(event) {
    if (this.uploads.size > 0) {
      event.preventDefault()
    } else if (this.editorTarget.editor.getDocument().getAttachments().length > this.imageLimitValue) {
      event.preventDefault()
      this.showError("image_limit")
    }
  }

  abortUploads() {
    const requests = Array.from(this.uploads.values())
    this.uploads.clear()
    requests.forEach(request => request.abort())
  }

  updateUploadState() {
    const uploading = this.uploads.size > 0
    this.saveTarget.disabled = uploading
    this.uploadStatusTarget.hidden = !uploading
  }

  filterPaste(event) {
    if (!event.paste?.html) return

    const template = this.parseHTML(event.paste.html)
    let rejected = false
    template.content.querySelectorAll("[data-trix-attachment]").forEach(node => {
      const attributes = this.imageAttributes(node)
      if (node.matches("figure") && this.isLocalImage(attributes)) {
        const { bookNoteImageId, url, contentType } = attributes
        const figure = document.createElement("figure")
        figure.dataset.trixAttachment = JSON.stringify({ bookNoteImageId, url, contentType, alt: this.imageAltValue })
        node.replaceWith(figure)
      } else {
        node.remove()
        rejected = true
      }
    })
    template.content.querySelectorAll("img, picture, svg, audio, video, source, object, embed, iframe, action-text-attachment").forEach(node => {
      node.remove()
      rejected = true
    })
    if (rejected) this.showError("attachments_not_allowed")
    event.paste.html = template.innerHTML
  }

  bodySnapshot(html) {
    const template = this.parseHTML(html)
    // Image previews can update their dimensions after the modal has opened.
    template.content.querySelectorAll("figure[data-trix-attachment]").forEach(node => {
      const attributes = this.imageAttributes(node)
      if (!this.isLocalImage(attributes)) return

      const marker = document.createElement("span")
      marker.dataset.bookNoteImageId = attributes.bookNoteImageId
      node.replaceWith(marker)
    })
    return template.innerHTML
  }

  parseHTML(html) {
    const template = document.createElement("template")
    template.innerHTML = html
    return template
  }

  imageAttributes(node) {
    try {
      return JSON.parse(node.getAttribute("data-trix-attachment")) || {}
    } catch {
      return {}
    }
  }

  isLocalImage({ bookNoteImageId, url, contentType, sgid, href, content }) {
    return /^[1-9]\d*$/.test(String(bookNoteImageId)) && url === `${this.uploadUrlValue}/${bookNoteImageId}` &&
      contentType === "image/webp" && !sgid && !href && !content
  }

  rejectAttachment(attachment, error, message) {
    attachment.remove()
    this.showError(error, message)
  }

  showError(error, message) {
    this.attachmentErrorTarget.textContent = message || this.errorsValue[error] || this.errorsValue.upload_failed
    this.attachmentErrorTarget.hidden = false
  }
}
