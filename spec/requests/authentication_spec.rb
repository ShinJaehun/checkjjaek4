require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "POST /users" do
    it "creates a user and redirects to the home feed" do
      expect {
        post user_registration_path, params: {
          user: {
            name: "New Reader",
            email: "new-reader@example.com",
            password: "password123!",
            password_confirmation: "password123!"
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(root_path)
    end

    it "does not permit global admin through registration params" do
      post user_registration_path, params: {
        user: {
          name: "Regular Reader",
          email: "regular-reader@example.com",
          password: "password123!",
          password_confirmation: "password123!",
          global_admin: true
        }
      }

      expect(User.find_by!(email: "regular-reader@example.com")).not_to be_global_admin
    end
  end

  describe "POST /users/sign_in" do
    it "signs in and redirects to the home feed" do
      user = User.create!(
        name: "Signed In Reader",
        email: "signed-in@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )

      post user_session_path, params: {
        user: {
          email: user.email,
          password: "password123!"
        }
      }

      expect(response).to redirect_to(root_path)
    end

    it "shows the same generic message for an unknown email and a wrong password" do
      User.create!(name: "Reader", email: "reader@example.com", password: "password123!")

      [ "reader@example.com", "missing@example.com" ].each do |email|
        post user_session_path, params: { user: { email:, password: "wrong-password" } }, headers: { "ACCEPT" => "text/html" }
        expect(response.body).to include(I18n.t("auth.alerts.invalid_credentials"))
      end
    end

    it "shows the public suspension reason only after correct credentials" do
      user = User.create!(name: "Suspended", email: "suspended-sign-in@example.com", password: "password123!", suspended_at: Time.current)
      actor = User.create!(name: "Admin", email: "suspension-login-admin@example.com", password: "password123!", global_admin: true)
      ModerationAction.create!(target: user, actor:, action_type: :suspend, public_reason: "PUBLIC_SUSPENSION_REASON")

      post user_session_path, params: { user: { email: user.email, password: "password123!" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("auth.alerts.suspended", reason: "PUBLIC_SUSPENSION_REASON"))
      expect(response).not_to redirect_to(root_path)

      post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }

      expect(response.body).not_to include("PUBLIC_SUSPENSION_REASON")
      expect(response.body).not_to include(I18n.t("auth.alerts.suspended_fallback"))
    end

    it "shows the localized label for a predefined suspension reason" do
      user = User.create!(name: "Suspended", email: "keyed-suspension-sign-in@example.com", password: "password123!", suspended_at: Time.current)
      actor = User.create!(name: "Admin", email: "keyed-suspension-admin@example.com", password: "password123!", global_admin: true)
      ModerationAction.create!(target: user, actor:, action_type: :suspend, public_reason: "spam_or_manipulation")

      post user_session_path, params: { user: { email: user.email, password: "password123!" } }

      expect(response.body).to include(I18n.t("auth.alerts.suspended", reason: I18n.t("users.suspension_reasons.spam_or_manipulation")))
      expect(response.body).not_to include("spam_or_manipulation")
    end

    it "uses a generic suspension message when the audit row is unexpectedly missing" do
      user = User.create!(name: "Suspended", email: "suspended-fallback@example.com", password: "password123!", suspended_at: Time.current)

      post user_session_path, params: { user: { email: user.email, password: "password123!" } }

      expect(response.body).to include(I18n.t("auth.alerts.suspended_fallback"))
    end
  end

  it "ends an existing suspended session before the next request can mutate data" do
    user = User.create!(name: "Existing Session", email: "suspended-session@example.com", password: "password123!")
    actor = User.create!(name: "Admin", email: "suspended-session-admin@example.com", password: "password123!", global_admin: true)
    sign_in user
    Users::SuspendAccount.new(user, actor:, public_reason: "other").call!

    expect {
      post jjaeks_path, params: { jjaek: { content: "BLOCKED_SUSPENDED_MUTATION" } }
    }.not_to change(Jjaek, :count)

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to include(I18n.t("users.suspension_reasons.other"))

    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "removes admin access from an existing session while retaining ordinary access" do
    admin = User.create!(name: "Role session admin", email: "role-session-admin@example.com", password: "password123!", global_admin: true)
    other_admin = User.create!(name: "Remaining admin", email: "role-session-remaining@example.com", password: "password123!", global_admin: true)
    reader = User.create!(name: "Reader", email: "role-session-reader@example.com", password: "password123!")
    sign_in admin

    get admin_users_path
    expect(response).to have_http_status(:ok)

    GlobalAdminRoles::Change.new(
      user_id: admin.id, action: :revoke, reason: "Staffing change",
      operator_uid: 1000, operator_account: "deploy", server_hostname: "app-server",
      execution_id: SecureRandom.uuid
    ).call!
    expect(other_admin.reload).to be_global_admin

    get admin_users_path
    expect(response).to redirect_to(root_path)
    expect {
      post admin_user_account_suspensions_path(reader), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to redirect_to(root_path)

    get root_path
    expect(response).to have_http_status(:ok)
    expect {
      post jjaeks_path, params: { jjaek: { content: "Ordinary access after role revocation" } }
    }.to change(Jjaek, :count).by(1)
  end

  it "does not restore admin access from a remember-me cookie after revocation" do
    admin = User.create!(name: "Remembered admin", email: "role-remember-admin@example.com", password: "password123!", global_admin: true)
    User.create!(name: "Remaining admin", email: "role-remember-remaining@example.com", password: "password123!", global_admin: true)

    post user_session_path, params: {
      user: { email: admin.email, password: "password123!", remember_me: "1" }
    }
    remember_cookie = Array(response.headers.fetch("Set-Cookie")).flat_map { |value| value.to_s.split("\n") }
      .find { |cookie| cookie.start_with?("remember_user_token=") }
      &.split(";", 2)&.first
    expect(remember_cookie).to be_present

    remembered_session = ActionDispatch::Integration::Session.new(Rails.application)
    remembered_session.get(admin_users_path, headers: { "Cookie" => remember_cookie })
    expect(remembered_session.response).to have_http_status(:ok)

    GlobalAdminRoles::Change.new(
      user_id: admin.id, action: :revoke, reason: "Staffing change",
      operator_uid: 1000, operator_account: "deploy", server_hostname: "app-server",
      execution_id: SecureRandom.uuid
    ).call!

    revoked_session = ActionDispatch::Integration::Session.new(Rails.application)
    revoked_session.get(admin_users_path, headers: { "Cookie" => remember_cookie })
    expect(revoked_session.response).to redirect_to(root_path)
    revoked_session.get(root_path)
    expect(revoked_session.response).to have_http_status(:ok)
  end

  it "keeps a suspended author's existing public content visible" do
    author = User.create!(name: "Suspended Author", email: "suspended-content-author@example.com", password: "password123!", suspended_at: Time.current)
    viewer = User.create!(name: "Viewer", email: "suspended-content-viewer@example.com", password: "password123!")
    jjaek = author.jjaeks.create!(content: "VISIBLE_SUSPENDED_AUTHOR_CONTENT")
    sign_in viewer

    get jjaek_path(jjaek)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("VISIBLE_SUSPENDED_AUTHOR_CONTENT")
  end

  describe "PATCH /users" do
    it "does not permit global admin through account update params" do
      user = User.create!(name: "Reader", email: "account-update-reader@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in user

      patch user_registration_path, params: {
        user: { name: "Updated Reader", global_admin: true, current_password: "password123!" }
      }

      expect(user.reload).not_to be_global_admin
    end

    it "ends a suspended existing session before a Devise account update" do
      user = User.create!(name: "Original Name", email: "suspended-account-update@example.com", password: "password123!")
      actor = User.create!(name: "Admin", email: "suspended-account-update-admin@example.com", password: "password123!", global_admin: true)
      sign_in user
      Users::SuspendAccount.new(user, actor:, public_reason: "other").call!

      patch user_registration_path, params: {
        user: { name: "Blocked Name", current_password: "password123!" }
      }

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.name).to eq("Original Name")

      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "DELETE /users/sign_out" do
    it "signs out and redirects to the sign-in page" do
      user = User.create!(
        name: "Signed Out Reader",
        email: "signed-out@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )
      sign_in user

      delete destroy_user_session_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
