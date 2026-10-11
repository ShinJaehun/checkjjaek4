require "uri"

class Book < ApplicationRecord
  class IdentityConflict < StandardError; end

  has_many :bookshelf_entries, dependent: :destroy
  has_many :users, through: :bookshelf_entries
  has_many :jjaeks, dependent: :destroy

  validates :title, presence: true
  validate :validate_urls, if: -> { new_record? || will_save_change_to_external_url? || will_save_change_to_thumbnail? }
  before_validation :set_canonical_isbn, if: -> { new_record? || will_save_change_to_isbn? }

  def self.canonical_isbn_for(raw)
    tokens = raw.to_s.upcase.split(/[[:space:]]+/).map { |token| token.delete("-") }
    compact = raw.to_s.upcase.gsub(/[-[:space:]]/, "")
    expected_count = { 10 => 1, 13 => 1, 20 => 2, 23 => 2, 26 => 2 }[compact.length]
    if expected_count && tokens.count { |token| valid_isbn13?(token) || valid_isbn10?(token) } < expected_count
      tokens.concat(
        case compact.length
        when 10, 13 then [ compact ]
        when 20 then [ compact[0, 10], compact[10, 10] ]
        when 23 then [ compact[0, 10], compact[10, 13], compact[0, 13], compact[13, 10] ]
        when 26 then [ compact[0, 13], compact[13, 13] ]
        else []
        end
      )
    end
    isbn13s = tokens.select { |token| valid_isbn13?(token) }.uniq
    raise IdentityConflict if isbn13s.size > 1
    return isbn13s.first if isbn13s.any?

    isbn10s = tokens.select { |token| valid_isbn10?(token) }.map { |token| isbn10_to13(token) }.uniq
    raise IdentityConflict if isbn10s.size > 1

    isbn10s.first
  end

  def self.valid_http_url?(value)
    uri = URI.parse(value.to_s)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

    host = uri.host.downcase
    host.length <= 253 && host.include?(".") &&
      host.split(".").all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) } &&
      !host.match?(/\A\d+(?:\.\d+){3}\z/)
  rescue URI::InvalidURIError
    false
  end

  def self.find_or_initialize_from_search(attributes)
    attrs = attributes.to_h.symbolize_keys.slice(
      :title, :authors_text, :publisher, :thumbnail, :isbn, :description, :external_url
    )

    attrs[:title] = attrs[:title].to_s.strip
    attrs[:authors_text] = attrs[:authors_text].to_s.strip
    attrs[:publisher] = attrs[:publisher].to_s.strip
    attrs[:thumbnail] = attrs[:thumbnail].to_s.strip.presence
    attrs[:thumbnail] = nil unless valid_http_url?(attrs[:thumbnail])
    attrs[:isbn] = attrs[:isbn].to_s.strip.presence
    attrs[:description] = attrs[:description].to_s.strip
    attrs[:external_url] = attrs[:external_url].to_s.strip.presence
    attrs[:external_url] = nil unless valid_http_url?(attrs[:external_url])

    canonical_isbn = canonical_isbn_for(attrs[:isbn])
    isbn_book = find_by(canonical_isbn: canonical_isbn) if canonical_isbn
    url_book = find_by(external_url: attrs[:external_url]) if attrs[:external_url]
    raise IdentityConflict if isbn_book && url_book && isbn_book != url_book
    raise IdentityConflict if canonical_isbn && url_book && url_book.canonical_isbn != canonical_isbn

    isbn_book || (canonical_isbn.nil? && url_book) || new(attrs.merge(canonical_isbn: canonical_isbn))
  end

  def self.valid_isbn10?(value)
    value.match?(/\A\d{9}[\dX]\z/) &&
      value.chars.each_with_index.sum { |digit, index| (digit == "X" ? 10 : digit.to_i) * (10 - index) } % 11 == 0
  end

  def self.valid_isbn13?(value)
    value.match?(/\A97[89]\d{10}\z/) &&
      value.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) } % 10 == 0
  end

  def self.isbn10_to13(value)
    first_twelve = "978#{value.first(9)}"
    sum = first_twelve.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) }
    "#{first_twelve}#{(10 - sum % 10) % 10}"
  end

  private_class_method :valid_isbn10?, :valid_isbn13?, :isbn10_to13

  private

  def set_canonical_isbn
    self.canonical_isbn = self.class.canonical_isbn_for(isbn)
  rescue IdentityConflict
    errors.add(:isbn, :invalid)
  end

  def validate_urls
    errors.add(:external_url, :invalid) if external_url.present? && !self.class.valid_http_url?(external_url)
    errors.add(:thumbnail, :invalid) if thumbnail.present? && !self.class.valid_http_url?(thumbnail)
  end
end
