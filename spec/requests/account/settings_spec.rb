require "rails_helper"

RSpec.describe "Settings", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "settings-reader@example.com", password: "password123!") }

  it "requires sign in" do
    get account_settings_path
    expect(response).to redirect_to(new_user_session_path)

    patch account_settings_path, params: { user: { allows_new_followers: "0" } }
    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.allows_new_followers).to be(true)
  end

  it "shows only the signed-in user's three interaction settings" do
    sign_in user
    get account_settings_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#interaction-preferences")).to be_present
    expect(page.at_css("form[action='#{account_settings_path}']")).to be_present
    %w[accepts_book_friend_requests accepts_group_invitations allows_new_followers].each do |field|
      expect(page.at_css("input[type='checkbox'][name='user[#{field}]']")).to be_present
    end
    expect(page.at_css("nav a[href='#{account_settings_path}']")).to be_present
  end

  it "saves all three booleans, including unchecked checkboxes, then redirects back" do
    sign_in user
    patch account_settings_path, params: {
      user: {
        accepts_book_friend_requests: "0",
        accepts_group_invitations: "0",
        allows_new_followers: "0"
      }
    }

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload).to have_attributes(
      accepts_book_friend_requests: false,
      accepts_group_invitations: false,
      allows_new_followers: false
    )
  end

  it "does not update another user's settings through submitted attributes" do
    other = User.create!(name: "Other", email: "settings-other@example.com", password: "password123!")
    sign_in user

    patch account_settings_path, params: { user: { id: other.id, global_admin: true, allows_new_followers: "0" } }

    expect(user.reload.allows_new_followers).to be(false)
    expect(user.global_admin?).to be(false)
    expect(other.reload.allows_new_followers).to be(true)
  end
end
