require "rails_helper"

RSpec.describe "Follows", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader3@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:other_user) { User.create!(name: "Other", email: "other@example.com", password: "password123!", password_confirmation: "password123!") }

  it "lets a signed-in user follow another user" do
    sign_in user

    expect {
      post user_follow_path(other_user)
    }.to change(Follow, :count).by(1)
  end
end
