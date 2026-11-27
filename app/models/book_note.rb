class BookNote < ApplicationRecord
  MAX_BODY_LENGTH = 10_000
  IMAGE_ATTRIBUTE = "book-note-image-id".freeze
  IMAGE_SELECTOR = "action-text-attachment[#{IMAGE_ATTRIBUTE}]".freeze
  ATTACHMENT_SELECTOR = "action-text-attachment, [data-trix-attachment]".freeze
  MEDIA_SELECTOR = "img, picture, svg, audio, video, source, object, embed, iframe, input[type=file]".freeze
  TRIX_IMAGE_ATTRIBUTES = %w[bookNoteImageId contentType url filename filesize width height previewable alt].freeze

  belongs_to :user_book
  has_many :book_note_images
  has_rich_text :body

  validate :validate_body

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.image_id(value)
    return unless (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[1-9]\d{0,18}\z/)

    value.to_i if value.to_i <= (2**63 - 1)
  end

  def body=(value)
    @invalid_attachment = false
    # Rewrite attachments before Action Text can resolve signed IDs or URLs.
    fragment = ActionText::Fragment.wrap(value).replace(ATTACHMENT_SELECTOR) do |node|
      if (image_id = submitted_image_id(node))
        marker = ActionText::HtmlConversion.create_element("action-text-attachment", IMAGE_ATTRIBUTE => image_id.to_s)
        ActionText::HtmlConversion.node_to_html(marker)
      else
        @invalid_attachment = true
        ""
      end
    end
    if fragment.find_all(MEDIA_SELECTOR).any?
      @invalid_attachment = true
      fragment = fragment.replace(MEDIA_SELECTOR) { "" }
    end
    body.body = fragment.to_html
  end

  def editable_body
    body.body || ActionText::Content.new
  end

  def images_for_body(allow_temporary: false)
    ids = body_image_ids.uniq
    return {} if ids.empty? || !user_book

    user_book.book_note_images.where(id: ids.first(BookNoteImage::MAX_PER_NOTE + 1), user_id: user_book.user_id).select do |image|
      (persisted? && image.attached? && image.book_note_id == id) || (allow_temporary && image.temporary_available?)
    end.index_by(&:id)
  end

  def update_content(attributes, user:)
    @updating_images = attributes.key?(:body)
    assign_attributes(attributes)
    draft_title = title
    draft_body = editable_body.to_html if @updating_images
    self.class.transaction(requires_new: true) do
      save!
      synchronize_images!(user) if @updating_images
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record.equal?(self)

    false
  rescue ActiveRecord::RecordNotFound
    self.title = draft_title
    body.body = draft_body if draft_body
    errors.add(:body, :image_unavailable)
    false
  rescue BookNoteImage::AttachmentLimit
    self.title = draft_title
    body.body = draft_body if draft_body
    errors.add(:body, :image_limit, count: BookNoteImage::MAX_PER_NOTE)
    false
  ensure
    @updating_images = false
  end

  private

  def body_image_ids
    editable_body.fragment.find_all(IMAGE_SELECTOR).filter_map { |node| self.class.image_id(node[IMAGE_ATTRIBUTE]) }
  end

  def submitted_image_id(node)
    if node.name == "action-text-attachment"
      return self.class.image_id(node[IMAGE_ATTRIBUTE]) if node.attribute_nodes.map(&:name) == [ IMAGE_ATTRIBUTE ] && node.inner_html.blank?

      return
    end
    return unless node.name == "figure" && user_book&.book_id

    attributes = JSON.parse(node["data-trix-attachment"].to_s)
    return unless attributes.is_a?(Hash) && (attributes.keys - TRIX_IMAGE_ATTRIBUTES).empty?

    image_id = self.class.image_id(attributes["bookNoteImageId"])
    return unless image_id && attributes["contentType"] == "image/webp"

    path = Rails.application.routes.url_helpers.book_book_note_image_path(user_book.book_id, image_id)
    return unless attributes["url"] == path

    media = node.css("#{ATTACHMENT_SELECTOR}, #{MEDIA_SELECTOR}")
    return if media.size > 1 || media.any? { |child| child.name != "img" || child.parent != node || child["src"] != path || child.key?("srcset") }

    image_id
  rescue JSON::ParserError
    nil
  end

  def synchronize_images!(user)
    ids = body_image_ids.uniq
    images = images_for_body(allow_temporary: true)
    book_note_images.where.not(id: ids).each { |image| image.discard_from!(self, user:) }
    ids.each { |image_id| images.fetch(image_id) { raise ActiveRecord::RecordNotFound }.attach_to!(self, user:) }
  end

  def validate_body
    content = body.body
    if @invalid_attachment || (content && content.fragment.find_all("#{MEDIA_SELECTOR}, [data-trix-attachment], action-text-attachment:not([#{IMAGE_ATTRIBUTE}])").any?)
      return errors.add(:body, :attachments_not_allowed)
    end
    return errors.add(:body, :blank) unless content

    # Action Text's plain-text conversion adds bullets and quotation marks for empty blocks.
    visible_text = content.fragment.replace("script, style, template, noscript") { "" }.source.text
    return errors.add(:body, :blank) unless visible_text.match?(/[^[:space:]\p{Cf}]/)

    if content.to_plain_text.length > MAX_BODY_LENGTH
      return errors.add(:body, :too_long, count: MAX_BODY_LENGTH)
    end

    ids = body_image_ids
    return errors.add(:body, :image_limit, count: BookNoteImage::MAX_PER_NOTE) if ids.size > BookNoteImage::MAX_PER_NOTE

    if ids.any? && images_for_body(allow_temporary: @updating_images).size != ids.uniq.size
      errors.add(:body, :image_unavailable)
    end
  end
end
