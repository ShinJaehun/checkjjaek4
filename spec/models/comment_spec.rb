require "rails_helper"

RSpec.describe Comment, type: :model do
  it "requires content" do
    user = User.create!(name: "Reader", email: "comment@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(title: "북짹", authors_text: "저자")
    jjaek = user.jjaeks.create!(book:, content: "Jjaek")
    comment = described_class.new(user:, jjaek:, content: "")

    expect(comment).not_to be_valid
  end
end
