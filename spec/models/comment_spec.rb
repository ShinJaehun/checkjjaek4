require "rails_helper"

RSpec.describe Comment, type: :model do
  it "requires content" do
    user = User.create!(name: "Reader", email: "comment@example.com", password: "password123!", password_confirmation: "password123!")
    book = Book.create!(title: "북짹", authors_text: "저자")
    jjaek = user.jjaeks.create!(book:, content: "Jjaek")
    comment = described_class.new(user:, jjaek:, content: "")

    expect(comment).not_to be_valid
  end

  it "keeps moderation hiding separate from author deletion" do
    user = User.create!(name: "Reader", email: "comment-hidden@example.com", password: "password123!")
    jjaek = user.jjaeks.create!(content: "Jjaek")
    comment = jjaek.comments.create!(user:, content: "Hidden comment")

    comment.update!(hidden_at: Time.current)

    expect(comment.reload).to be_hidden
    expect(comment.content).to eq("Hidden comment")
    expect(comment.jjaek).to eq(jjaek)
  end
end
