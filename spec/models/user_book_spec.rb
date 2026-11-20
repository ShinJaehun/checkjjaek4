require "rails_helper"

RSpec.describe UserBook, type: :model do
  let(:user) { User.create!(name: "Reader", email: "user-book@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "독서 기록") }

  it "defaults status to nil and allows it to be cleared" do
    user_book = described_class.create!(user:, book:)

    expect(user_book.status).to be_nil
    user_book.update!(status: :reading)
    user_book.update!(status: nil)
    expect(user_book.reload.status).to be_nil
  end

  it "validates status against the declared enum values" do
    user_book = described_class.new(user:, book:, status: :archived)

    expect(user_book).not_to be_valid
    expect(user_book.errors.of_kind?(:status, :inclusion)).to be(true)
  end

  it "enforces one reading record per user and book in the database" do
    described_class.create!(user:, book:)

    expect {
      described_class.transaction(requires_new: true) { described_class.create!(user:, book:) }
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
