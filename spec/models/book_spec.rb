require "rails_helper"

RSpec.describe Book, type: :model do
  describe ".find_or_initialize_from_search" do
    it "normalizes blankable search attributes before assignment" do
      book = described_class.find_or_initialize_from_search(
        title: "  검색한 책  ",
        authors_text: "  검색 저자  ",
        publisher: "  검색 출판사  ",
        thumbnail: "   ",
        isbn: "   ",
        description: "  검색 설명  ",
        external_url: "   "
      )

      expect(book).to be_a_new(described_class)
      expect(book.title).to eq("검색한 책")
      expect(book.authors_text).to eq("검색 저자")
      expect(book.publisher).to eq("검색 출판사")
      expect(book.thumbnail).to be_nil
      expect(book.isbn).to be_nil
      expect(book.description).to eq("검색 설명")
      expect(book.external_url).to be_nil
    end

    it "reuses an existing book matched by isbn" do
      existing_book = described_class.create!(
        title: "기존 제목",
        authors_text: "기존 저자",
        isbn: "9780000000001",
        external_url: "https://example.com/original"
      )

      resolved_book = described_class.find_or_initialize_from_search(
        title: "새 제목",
        authors_text: "새 저자",
        isbn: " 9780000000001 ",
        external_url: "https://example.com/updated"
      )

      expect(resolved_book).to eq(existing_book)
      expect(resolved_book.title).to eq("새 제목")
      expect(resolved_book.authors_text).to eq("새 저자")
      expect(resolved_book.external_url).to eq("https://example.com/updated")
    end

    it "reuses an existing book matched by external_url when isbn is missing" do
      existing_book = described_class.create!(
        title: "기존 제목",
        authors_text: "기존 저자",
        external_url: "https://example.com/books/1"
      )

      resolved_book = described_class.find_or_initialize_from_search(
        title: "새 제목",
        authors_text: "새 저자",
        external_url: " https://example.com/books/1 "
      )

      expect(resolved_book).to eq(existing_book)
      expect(resolved_book.title).to eq("새 제목")
      expect(resolved_book.authors_text).to eq("새 저자")
    end
  end
end
