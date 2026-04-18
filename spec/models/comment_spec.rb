require "rails_helper"

RSpec.describe Comment, type: :model do
  it "requires content" do
    user = User.create!(name: "Reader", email: "comment@example.com", password: "password123!", password_confirmation: "password123!")
    post_record = user.posts.create!(content: "Post")
    comment = described_class.new(user: user, post: post_record, content: "")

    expect(comment).not_to be_valid
  end
end
