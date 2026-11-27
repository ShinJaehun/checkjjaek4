class BookNote < ApplicationRecord
  MAX_BODY_LENGTH = 10_000
  ATTACHMENT_SELECTOR = "action-text-attachment, [data-trix-attachment], img, picture, svg, " \
                        "audio, video, source, object, embed, iframe, input[type=file]".freeze

  belongs_to :user_book
  has_many :book_note_images
  has_rich_text :body

  validate :validate_body

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def body=(value)
    # Inspect submitted markup before Action Text interprets Trix attachment metadata.
    fragment = ActionText::Fragment.wrap(value)
    @submitted_attachments = fragment.find_all(ATTACHMENT_SELECTOR).any?
    value = fragment.replace(ATTACHMENT_SELECTOR) { "" }.to_html if @submitted_attachments
    body.body = value
  end

  def editable_body
    body.body || ActionText::Content.new
  end

  private

  def validate_body
    content = body.body
    if @submitted_attachments || (content && content.fragment.find_all(ATTACHMENT_SELECTOR).any?)
      return errors.add(:body, :attachments_not_allowed)
    end
    return errors.add(:body, :blank) unless content

    # Action Text's plain-text conversion adds bullets and quotation marks for empty blocks.
    visible_text = content.fragment.replace("script, style, template, noscript") { "" }.source.text
    return errors.add(:body, :blank) unless visible_text.match?(/[^[:space:]\p{Cf}]/)

    if content.to_plain_text.length > MAX_BODY_LENGTH
      errors.add(:body, :too_long, count: MAX_BODY_LENGTH)
    end
  end
end
