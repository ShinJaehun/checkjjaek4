require "rails_helper"

RSpec.describe Post, type: :model do
  it "defaults visibility to public_feed" do
    user = User.create!(name: "Reader", email: "visibility@example.com", password: "password123!", password_confirmation: "password123!")
    post_record = described_class.create!(user: user, content: "Visible by default")

    expect(post_record.public_feed?).to be(true)
  end
end
