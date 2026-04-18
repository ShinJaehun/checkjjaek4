require "rails_helper"

RSpec.describe Like, type: :model do
  it "prevents duplicate likes for the same post" do
    user = User.create!(name: "Reader", email: "dup-like@example.com", password: "password123!", password_confirmation: "password123!")
    post_record = user.posts.create!(content: "Post")
    described_class.create!(user: user, post: post_record)

    duplicate = described_class.new(user: user, post: post_record)

    expect(duplicate).not_to be_valid
  end
end
