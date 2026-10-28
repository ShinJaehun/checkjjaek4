module BookshelfEntriesHelper
  READING_ICON_PATHS = {
    "wish" => "M6 3h12v18l-6-4-6 4V3Z",
    "reading" => "M12 5C8 2 3 3 3 3v16s5-1 9 2c4-3 9-2 9-2V3s-5-1-9 2Zm0 0v16",
    "finished" => "m5 12 4 4L19 6",
    "loved_it" => "M20 5c-2-2-5-2-8 1-3-3-6-3-8-1-4 4 0 9 8 15 8-6 12-11 8-15Z",
    "really_loved_it" => "m12 3 3 6 6 1-4 5 1 6-6-3-6 3 1-6-4-5 6-1 3-6Z",
    "stayed_with_me" => "M12 3c4 5 7 8 7 12a7 7 0 0 1-14 0c0-4 3-7 7-12Z",
    "want_to_reread" => "M4 10a8 8 0 1 1 1 8M4 4v6h6",
    "recommended_to_me" => "M20 14a3 3 0 0 1-3 3H9l-5 4V6a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v8ZM16 10H8m3-3-3 3 3 3",
    "want_to_recommend" => "m21 3-7 18-3-8-8-3 18-7ZM11 13 21 3"
  }.freeze

  def reading_state_icon(key)
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round",
            class: "h-4 w-4 shrink-0", aria: { hidden: true }) do
      tag.path(d: READING_ICON_PATHS.fetch(key.to_s, "M5 5h14v14H5Z"))
    end
  end

  def reading_sticker_label(sticker)
    t("reading_experience.stickers.#{sticker.key}", default: sticker.name)
  end

  def reading_status_label(status)
    return if status.blank?

    t("bookshelf_entries.statuses.#{status}")
  end

  def reading_badge_classes(kind, selectable: false, icon_only: false)
    base = "inline-flex min-w-0 max-w-full items-center gap-1.5 border text-xs font-medium"
    spacing = if selectable
      "ui-choice"
    else
      icon_only ? "shrink-0 p-0.5" : "px-2.5 py-1"
    end
    shape = kind == :status ? "rounded-lg" : "rounded-full"
    colors = if selectable
      if kind == :status
        "border-stone-300 bg-white text-stone-700 has-[:checked]:border-stone-700 has-[:checked]:bg-stone-100 has-[:checked]:text-stone-900"
      else
        "border-stone-300 bg-white text-stone-700 has-[:checked]:border-amber-600 has-[:checked]:bg-amber-50 has-[:checked]:text-amber-900"
      end
    else
      kind == :status ? "border-stone-300 bg-stone-100 text-stone-700" : "border-amber-200 bg-amber-50 text-amber-900"
    end
    interaction = "cursor-pointer has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-stone-500" if selectable

    [ base, spacing, shape, colors, interaction ].compact.join(" ")
  end

  def reading_status_content(status)
    return if status.blank?

    safe_join([ reading_state_icon(status), tag.span(reading_status_label(status), class: "min-w-0 truncate") ])
  end

  def reading_sticker_content(sticker)
    safe_join([ reading_state_icon(sticker.key), tag.span(reading_sticker_label(sticker), class: "min-w-0 truncate") ])
  end

  def reading_status_badge(status)
    return if status.blank?

    tag.span(reading_status_content(status), class: reading_badge_classes(:status), title: reading_status_label(status), data: { reading_status: status })
  end

  def reading_sticker_badge(sticker, icon_only: false)
    label = reading_sticker_label(sticker)
    options = { class: reading_badge_classes(:sticker, icon_only: icon_only), title: label, data: { reading_sticker: sticker.key } }
    options.merge!(role: "img", aria: { label: label }) if icon_only

    content = icon_only ? reading_state_icon(sticker.key) : reading_sticker_content(sticker)
    tag.span(content, **options)
  end

  def bookshelf_entry_book_hidden_fields(book)
    safe_join(
      [
        hidden_field_tag("book[title]", book.title),
        hidden_field_tag("book[authors_text]", book.authors_text),
        hidden_field_tag("book[publisher]", book.publisher),
        hidden_field_tag("book[thumbnail]", book.thumbnail),
        hidden_field_tag("book[isbn]", book.isbn),
        hidden_field_tag("book[description]", book.description),
        hidden_field_tag("book[external_url]", book.external_url)
      ]
    )
  end
end
