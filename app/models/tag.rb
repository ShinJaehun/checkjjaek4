class Tag < ApplicationRecord
  NAME_PATTERN = /\A[\p{Hangul}A-Za-z0-9_]+\z/u
  HASHTAG_PATTERN = /#([\p{Hangul}A-Za-z0-9_]+)/u

  has_many :jjaek_tags, dependent: :delete_all
  has_many :jjaeks, through: :jjaek_tags

  before_validation :normalize_name

  validates :name, presence: true, format: { with: NAME_PATTERN }

  def self.canonical_name(value)
    return unless value.is_a?(String)

    name = value.unicode_normalize(:nfc).downcase
    name if name.length <= 199 && NAME_PATTERN.match?(name)
  end

  def self.extract_names(content)
    content.to_s.scan(HASHTAG_PATTERN).flatten.filter_map { |name| canonical_name(name) }.uniq
  end

  private

  def normalize_name
    self.name = self.class.canonical_name(name) if name.present?
  end
end
