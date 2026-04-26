require "rails_helper"

RSpec.describe BookshelfEntry, type: :model do
  let(:user) { User.create!(name: "Reader", email: "visibility@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "북짹", authors_text: "저자") }

  it "defaults status to wish" do
    entry = described_class.create!(user:, book:)

    expect(entry.wish?).to be(true)
  end

  it "does not allow duplicate shelf entries for the same user and book" do
    described_class.create!(user:, book:)
    duplicate = described_class.new(user:, book:)

    expect(duplicate).not_to be_valid
  end

  it "validates status against the declared enum values" do
    entry = described_class.new(user:, book:, status: :archived)

    expect(entry).not_to be_valid
    expect(entry.errors.of_kind?(:status, :inclusion)).to be(true)
  end
end
