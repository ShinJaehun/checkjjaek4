class Book < ApplicationRecord
  has_many :bookshelf_entries, dependent: :destroy
  has_many :users, through: :bookshelf_entries
  has_many :jjaeks, dependent: :destroy

  validates :title, presence: true

  def self.find_or_initialize_from_search(attributes)
    attrs = attributes.to_h.symbolize_keys.slice(
      :title, :authors_text, :publisher, :thumbnail, :isbn, :description, :external_url
    )

    attrs[:title] = attrs[:title].to_s.strip
    attrs[:authors_text] = attrs[:authors_text].to_s.strip
    attrs[:publisher] = attrs[:publisher].to_s.strip
    attrs[:thumbnail] = attrs[:thumbnail].to_s.strip.presence
    attrs[:isbn] = attrs[:isbn].to_s.strip.presence
    attrs[:description] = attrs[:description].to_s.strip
    attrs[:external_url] = attrs[:external_url].to_s.strip.presence

    existing =
      if attrs[:isbn].present?
        find_by(isbn: attrs[:isbn])
      elsif attrs[:external_url].present?
        find_by(external_url: attrs[:external_url])
      end

    book = existing || new
    book.assign_attributes(attrs)
    book
  end
end
