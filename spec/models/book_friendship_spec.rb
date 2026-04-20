require "rails_helper"

RSpec.describe BookFriendship, type: :model do
  let(:user) { User.create!(name: "Reader", email: "reader-friendship@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "other-friendship@example.com", password: "password123!", password_confirmation: "password123!") }

  it "does not allow a user to add themselves as a book friend" do
    friendship = described_class.new(requester: user, addressee: user)

    expect(friendship).not_to be_valid
  end

  it "returns accepted friend ids for a user" do
    described_class.create!(requester: user, addressee: other_user, status: :accepted)

    expect(described_class.connected_ids_for(user)).to contain_exactly(other_user.id)
  end
end
