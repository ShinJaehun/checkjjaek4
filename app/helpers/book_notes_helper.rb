module BookNotesHelper
  def book_note_body_html(note, editor: false)
    images = note.images_for_body(allow_temporary: editor)
    fragment = note.editable_body.fragment.replace(BookNote::ATTACHMENT_SELECTOR) do |node|
      image = images[BookNote.image_id(node[BookNote::IMAGE_ATTRIBUTE])]
      next "" unless image

      path = book_book_note_image_path(note.user_book.book_id, image)
      if editor
        ActionText::TrixAttachment.from_attributes(book_note_image_id: image.id, content_type: "image/webp", url: path, alt: t("book_notes.image_alt"))
      else
        tag.figure(image_tag(path, alt: t("book_notes.image_alt"), loading: "lazy"), class: "book-note-image")
      end
    end
    attributes = sanitizer_allowed_attributes + (editor ? [ "data-trix-attachment" ] : [])
    sanitize(fragment.to_html, tags: sanitizer_allowed_tags, attributes:)
  end
end
