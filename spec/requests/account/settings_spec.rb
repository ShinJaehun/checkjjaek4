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

  it "shows separate profile and interaction forms and an account withdrawal link" do
    sign_in user
    get account_settings_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    profile_form = page.at_css("#profile-settings form[action='#{account_settings_path}']")
    interaction_form = page.at_css("#interaction-preferences form[action='#{account_settings_path}']")
    expect(profile_form).to be_present
    expect(interaction_form).to be_present
    expect(profile_form.at_css("input[name='user[name]'][value='Reader']")).to be_present
    %w[accepts_book_friend_requests accepts_group_invitations allows_new_followers].each do |field|
      expect(interaction_form.at_css("input[type='checkbox'][name='user[#{field}]']")).to be_present
      expect(profile_form.at_css("input[name='user[#{field}]']")).to be_nil
    end
    expect(interaction_form.at_css("input[name='user[name]']")).to be_nil
    expect(page.at_css("#account-management a[href='#{account_withdrawal_path}']")).to be_present
    expect(page.at_css("nav a[href='#{account_settings_path}']")).to be_present
    expect(page.at_css("nav a[href='#{account_relationships_path}']")).to be_present
    expect(page.at_css("nav a[href='#{user_path(user)}']")).to be_present
    expect(page.at_css("nav a[href='#{account_withdrawal_path}']")).to be_nil
  end

  it "updates the name without changing interaction preferences" do
    sign_in user

    patch account_settings_path, params: { user: { name: "Updated Reader" } }
    expect(response).to redirect_to(account_settings_path)
    expect(user.reload).to have_attributes(
      name: "Updated Reader",
      accepts_book_friend_requests: true,
      accepts_group_invitations: true,
      allows_new_followers: true
    )
  end

  it "saves all three booleans, including unchecked checkboxes, then redirects back" do
    sign_in user
    user.update!(name: "Unchanged Reader")
    patch account_settings_path, params: {
      user: {
        accepts_book_friend_requests: "0",
        accepts_group_invitations: "0",
        allows_new_followers: "0"
      }
    }

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload).to have_attributes(
      name: "Unchanged Reader",
      accepts_book_friend_requests: false,
      accepts_group_invitations: false,
      allows_new_followers: false
    )
  end

  it "does not update another user's settings through submitted attributes" do
    other = User.create!(name: "Other", email: "settings-other@example.com", password: "password123!")
    sign_in user

    patch account_settings_path, params: {
      user: { id: other.id, name: "Changed Reader", global_admin: true, allows_new_followers: "0" }
    }

    expect(user.reload).to have_attributes(name: "Changed Reader", allows_new_followers: false)
    expect(user.global_admin?).to be(false)
    expect(other.reload).to have_attributes(name: "Other", allows_new_followers: true)
  end

  it "keeps the existing account withdrawal confirmation page reachable from settings" do
    sign_in user

    get account_settings_path
    expect(response.body).to include("href=\"#{account_withdrawal_path}\"")

    get account_withdrawal_path
    expect(response).to have_http_status(:ok)
  end
end
