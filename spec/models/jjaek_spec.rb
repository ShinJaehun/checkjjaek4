require "rails_helper"

RSpec.describe Jjaek, type: :model do
  let(:user) { User.create!(name: "Reader", email: "reader-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "other-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "북짹", authors_text: "저자") }

  it "allows a jjaek without a book" do
    jjaek = described_class.new(user:, content: "책 없이 남기는 짹")

    expect(jjaek).to be_valid
  end

  it "allows a profile-context jjaek with a target user" do
    jjaek = described_class.new(user:, target_user: other_user, content: "프로필 문맥 짹")

    expect(jjaek).to be_valid
  end

  it "does not allow requoting a private jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :private_jjaek)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original)

    expect(requote).not_to be_valid
  end

  it "does not allow broader visibility than the original jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :book_friends)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original, visibility: :public_jjaek)

    expect(requote).not_to be_valid
    expect(requote.errors.of_kind?(:visibility, :cannot_exceed_quoted_visibility)).to be(true)
  end

  it "does not allow requoting another requote" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    first_requote = user.jjaeks.create!(book:, content: "첫 인용", quoted_jjaek: original)
    nested_requote = described_class.new(user:, book:, content: "중첩 인용", quoted_jjaek: first_requote)

    expect(nested_requote).not_to be_valid
  end

  it "counts only persisted comments when the association target includes a form object" do
    jjaek = user.jjaeks.create!(content: "댓글 집계")
    jjaek.comments.create!(user: other_user, content: "저장된 댓글")
    jjaek.comments.build(user:, content: "폼용 댓글")

    expect(jjaek.comments_count).to eq(1)
  end

  it "counts only persisted likes when the association target includes an unsaved like" do
    jjaek = user.jjaeks.create!(content: "좋아요 집계")
    jjaek.likes.create!(user: other_user)
    jjaek.likes.build(user:)

    expect(jjaek.likes_count).to eq(1)
  end
end
