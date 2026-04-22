require "rails_helper"

RSpec.describe Jjaek, type: :model do
  let(:user) { User.create!(name: "Reader", email: "reader-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "other-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "북짹", authors_text: "저자") }

  it "does not allow requoting a private jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :private_jjaek)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original)

    expect(requote).not_to be_valid
  end

  it "does not allow broader visibility than the original jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :book_friends)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original, visibility: :public_jjaek)

    expect(requote).not_to be_valid
  end

  it "does not allow requoting another requote" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    first_requote = user.jjaeks.create!(book:, content: "첫 인용", quoted_jjaek: original)
    nested_requote = described_class.new(user:, book:, content: "중첩 인용", quoted_jjaek: first_requote)

    expect(nested_requote).not_to be_valid
  end
end
