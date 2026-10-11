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
        isbn: "9780000000002",
        external_url: "https://example.com/original"
      )

      resolved_book = described_class.find_or_initialize_from_search(
        title: "새 제목",
        authors_text: "새 저자",
        isbn: " 9780000000002 ",
        external_url: "https://example.com/updated"
      )

      expect(resolved_book).to eq(existing_book)
      expect(resolved_book.title).to eq("기존 제목")
      expect(resolved_book.authors_text).to eq("기존 저자")
      expect(resolved_book.external_url).to eq("https://example.com/original")
      expect(resolved_book).not_to be_changed
    end

    it "uses a valid ISBN-13 in a composite result and preserves the original ISBN" do
      book = described_class.find_or_initialize_from_search(
        title: "복합 ISBN", isbn: "8996991341 9788996991342", external_url: "https://example.com/book"
      )

      expect(book.isbn).to eq("8996991341 9788996991342")
      expect(book).to be_valid
      expect(book.canonical_isbn).to eq("9788996991342")
    end

    it "rejects distinct valid ISBN-13 values in one result" do
      expect {
        described_class.find_or_initialize_from_search(title: "모호한 책", isbn: "9780000000002 9780000000019")
      }.to raise_error(Book::IdentityConflict)
    end

    it "converts ISBN-10 but does not treat a different 979 ISBN-13 as its alias" do
      expect(described_class.canonical_isbn_for("8996991341")).to eq("9788996991342")
      expect(described_class.canonical_isbn_for("8996991341 9790000000001")).to eq("9790000000001")
      expect(described_class.canonical_isbn_for("978-89-96991-34-2")).to eq("9788996991342")
      expect(described_class.canonical_isbn_for("978 89 96991 34 2")).to eq("9788996991342")
    end

    it "keeps invalid legacy ISBN text without a canonical ISBN" do
      book = described_class.create!(title: "레거시 책", isbn: "1111")

      expect(book.reload.isbn).to eq("1111")
      expect(book.canonical_isbn).to be_nil
    end

    it "rejects an ISBN and URL that identify different books" do
      described_class.create!(title: "ISBN 책", isbn: "9780000000002")
      described_class.create!(title: "URL 책", external_url: "https://example.com/other")

      expect {
        described_class.find_or_initialize_from_search(
          title: "충돌 책", isbn: "9780000000002", external_url: "https://example.com/other"
        )
      }.to raise_error(Book::IdentityConflict)
    end

    it "rejects unsafe URLs while allowing books without identifiers" do
      expect(described_class.new(title: "내부 책")).to be_valid
      expect(described_class.new(title: "위험한 주소", external_url: "javascript:alert(1)")).not_to be_valid
      expect(described_class.new(title: "로컬 표지", thumbnail: "http://localhost/cover.jpg")).not_to be_valid
    end

    it "enforces unique canonical ISBN and external URL in the database" do
      described_class.create!(title: "첫 책", isbn: "9780000000002", external_url: "https://example.com/unique")

      [
        { title: "같은 ISBN", canonical_isbn: "9780000000002" },
        { title: "같은 URL", external_url: "https://example.com/unique" }
      ].each do |attributes|
        expect {
          described_class.transaction(requires_new: true) { described_class.insert_all!([ attributes ]) }
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
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
      expect(resolved_book.title).to eq("기존 제목")
      expect(resolved_book.authors_text).to eq("기존 저자")
      expect(resolved_book).not_to be_changed
    end
  end
end
