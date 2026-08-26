require "rails_helper"

RSpec.describe BookFriendship, type: :model do
  let(:user) { User.create!(name: "Reader", email: "reader-friendship@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "other-friendship@example.com", password: "password123!", password_confirmation: "password123!") }

  it "does not allow a user to add themselves as a book friend" do
    friendship = described_class.new(requester: user, addressee: user)

    expect(friendship).not_to be_valid
  end

  it "does not allow another pending friendship for the same pair in either direction" do
    described_class.create!(requester: user, addressee: other_user)

    expect(described_class.new(requester: other_user, addressee: user)).not_to be_valid
    expect(described_class.new(requester: user, addressee: other_user)).not_to be_valid
  end

  it "does not allow another friendship when the pair is already accepted" do
    described_class.create!(requester: user, addressee: other_user, status: :accepted)

    expect(described_class.new(requester: other_user, addressee: user)).not_to be_valid
  end

  it "allows an existing pending friendship to be accepted" do
    friendship = described_class.create!(requester: user, addressee: other_user)

    expect(friendship.update(status: :accepted)).to be(true)
  end

  it "enforces pair uniqueness when validations are bypassed" do
    described_class.create!(requester: user, addressee: other_user)

    expect {
      described_class.insert_all!([
        {
          requester_id: other_user.id,
          addressee_id: user.id,
          status: described_class.statuses.fetch(:pending),
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "returns accepted friend ids for a user" do
    described_class.create!(requester: user, addressee: other_user, status: :accepted)

    expect(described_class.connected_ids_for(user)).to contain_exactly(other_user.id)
  end
end
