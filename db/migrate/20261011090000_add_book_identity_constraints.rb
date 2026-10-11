class AddBookIdentityConstraints < ActiveRecord::Migration[8.1]
  class BookRow < ActiveRecord::Base
    self.table_name = "books"
  end

  def up
    add_column :books, :canonical_isbn, :string
    BookRow.reset_column_information

    ids_by_isbn = Hash.new { |hash, key| hash[key] = [] }
    BookRow.select(:id, :isbn).find_each do |book|
      canonical_isbn = canonical_isbn_for(book.isbn)
      raise "Ambiguous ISBN for Book ##{book.id}" if canonical_isbn == :ambiguous

      ids_by_isbn[canonical_isbn] << book.id if canonical_isbn
    end

    duplicate = ids_by_isbn.find { |_, ids| ids.size > 1 }
    raise "Duplicate canonical ISBN for Books #{duplicate.last.join(', ')}" if duplicate

    duplicate_url = BookRow.where.not(external_url: nil)
      .group(:external_url).having("COUNT(*) > 1").limit(1).pluck(:external_url).first
    raise "Duplicate Book external URL: #{duplicate_url}" if duplicate_url

    ids_by_isbn.each do |canonical_isbn, ids|
      BookRow.where(id: ids.first).update_all(canonical_isbn: canonical_isbn)
    end

    add_index :books, :canonical_isbn, unique: true,
              where: "canonical_isbn IS NOT NULL", name: "index_books_on_canonical_isbn_unique"
    remove_index :books, name: "index_books_on_external_url"
    add_index :books, :external_url, unique: true,
              where: "external_url IS NOT NULL", name: "index_books_on_external_url_unique"
  end

  def down
    remove_index :books, name: "index_books_on_external_url_unique"
    add_index :books, :external_url
    remove_index :books, name: "index_books_on_canonical_isbn_unique"
    remove_column :books, :canonical_isbn
  end

  private

  def canonical_isbn_for(raw)
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
    return :ambiguous if isbn13s.size > 1
    return isbn13s.first if isbn13s.any?

    isbn10s = tokens.select { |token| valid_isbn10?(token) }.map { |token| isbn10_to13(token) }.uniq
    return :ambiguous if isbn10s.size > 1

    isbn10s.first
  end

  def valid_isbn10?(value)
    return false unless value.match?(/\A\d{9}[\dX]\z/)

    value.chars.each_with_index.sum { |digit, index| (digit == "X" ? 10 : digit.to_i) * (10 - index) } % 11 == 0
  end

  def valid_isbn13?(value)
    return false unless value.match?(/\A97[89]\d{10}\z/)

    value.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) } % 10 == 0
  end

  def isbn10_to13(value)
    first_twelve = "978#{value.first(9)}"
    sum = first_twelve.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) }
    "#{first_twelve}#{(10 - sum % 10) % 10}"
  end
end
