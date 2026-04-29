require "rails_helper"

RSpec.describe Like, type: :model do
  it "prevents duplicate likes for the same jjaek" do
    user = User.create!(name: "Reader", email: "dup-like@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(title: "북짹", authors_text: "저자")
    jjaek = user.jjaeks.create!(book:, content: "Jjaek")
    described_class.create!(user:, jjaek:)

    duplicate = described_class.new(user:, jjaek:)

    expect(duplicate).not_to be_valid
  end
end
