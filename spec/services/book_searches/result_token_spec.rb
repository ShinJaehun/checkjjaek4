require "rails_helper"

RSpec.describe BookSearches::ResultToken do
  let(:user) { User.create!(name: "Token reader", email: "publication-token@example.com", password: "password123!") }

  it "signs normalized publication metadata and restores a date string for Book assignment" do
    token = described_class.issue(
      { title: "출간 정보 책", translators_text: "첫 역자, 둘째 역자", published_on: Date.new(2026, 4, 22) }, user: user
    )

    attributes = described_class.verify(token, user: user)
    expect(attributes).to include(translators_text: "첫 역자, 둘째 역자", published_on: "2026-04-22")
    book = Book.find_or_initialize_from_search(attributes)
    expect(book.translators_text).to eq("첫 역자, 둘째 역자")
    expect(book.published_on).to eq(Date.new(2026, 4, 22))
    expect(described_class.verify("#{token}tampered", user: user)).to be_nil
    other = User.create!(name: "Other", email: "other-publication-token@example.com", password: "password123!")
    expect(described_class.verify(token, user: other)).to be_nil
  end

  it "keeps absent optional metadata nil" do
    token = described_class.issue({ title: "정보 없는 책" }, user: user)

    expect(described_class.verify(token, user: user)).to include(translators_text: nil, published_on: nil)
  end
end
