require "rails_helper"

RSpec.describe Follow, type: :model do
  it "prevents following yourself" do
    user = User.create!(name: "Reader", email: "self@example.com", password: "password123!", password_confirmation: "password123!")

    follow = described_class.new(follower: user, followee: user)

    expect(follow).not_to be_valid
  end
end
