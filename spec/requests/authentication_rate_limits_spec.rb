require "rails_helper"

RSpec.describe "Authentication rate limits", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:counter_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:counter_keys) { [] }
  let(:invitation) do
    admin = User.create!(name: "Admin", email: "rate-limit-admin@example.com", password: "password123!", global_admin: true)
    RegistrationInvitation.new(email: "invited@example.com", invited_by: admin)
  end
  let(:invitation_token) { invitation.issue_token!.tap { invitation.save! } }
  let(:sign_up_attributes) do
    { name: "Invited Reader", handle: "invited_reader", email: "spoofed@example.com", terms_accepted: "1",
      password: "submitted-secret123!", password_confirmation: "confirmation-secret123!" }
  end

  before do
    [ Users::RegistrationsController, Users::SessionsController ].each do |controller|
      allow(controller.cache_store).to receive(:increment) do |key, amount, **options|
        counter_keys << key
        counter_store.increment(key, amount, **options)
      end
    end
  end

  def attempt_login(email:, password: "wrong-password", ip: "192.0.2.1", headers: {})
    post user_session_path, params: { user: { email:, password: } },
                            headers: { "REMOTE_ADDR" => ip }.merge(headers)
  end

  def attempt_registration(headers: {}, invitation_token: nil, user: { name: "Reader", email: "reader@example.com" })
    post user_registration_path, params: { invitation_token:, user: }, headers:
  end

  it "allows 60 sign-up requests from one IP and rejects the 61st" do
    60.times { attempt_registration }
    expect(response).not_to have_http_status(:too_many_requests)

    token = invitation_token
    expect {
      attempt_registration(invitation_token: token, user: sign_up_attributes)
    }.not_to change(User, :count)

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
    expect(response.body).to include(I18n.t("auth.actions.sign_up"))
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('#flash-messages [role="alert"]').text.strip).to eq(I18n.t("auth.alerts.rate_limited"))
    expect(page.css('[role="alert"]').size).to eq(1)
    form = page.at_css(%(form[action="#{user_registration_path}"]))
    expect(form).to be_present
    expect(form.at_css('input[name="invitation_token"]')["value"]).to eq(token)
    expect(form.at_css('input[name="user[name]"]')["value"]).to eq(sign_up_attributes[:name])
    expect(form.at_css('input[name="user[handle]"]')["value"]).to eq(sign_up_attributes[:handle])
    expect(form.at_css('input[name="user[terms_accepted]"][type="checkbox"]')["checked"]).to be_present
    expect(form.text).to include(invitation.email, I18n.t("registration_invitations.password_reentry_notice"))
    expect(form.css('input[type="password"]').map { |field| field["value"] }).to all(be_blank)
    expect(response.body).not_to include(sign_up_attributes[:password], sign_up_attributes[:password_confirmation], "spoofed@example.com")
    expect(invitation.reload.consumed_at).to be_nil
  end

  it "does not restore a sign-up form for an invalid invitation when rate limited" do
    token = invitation_token
    invitation.cancel!
    allow(Users::RegistrationsController.cache_store).to receive(:increment).and_return(61)

    expect {
      attempt_registration(invitation_token: token, user: sign_up_attributes)
    }.not_to change(User, :count)

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{user_registration_path}"]))).to be_nil
    expect(response.body).not_to include(token, sign_up_attributes[:password], sign_up_attributes[:password_confirmation])
    expect(invitation.reload.consumed_at).to be_nil
  end

  it "allows 120 login attempts from one IP across distinct emails and rejects the next" do
    120.times { |index| attempt_login(email: "missing-#{index}@example.com") }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_login(email: "another-missing@example.com")

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("auth.alerts.login_rate_limited"))
  end

  it "limits an IP and normalized email combination to eight attempts" do
    8.times { attempt_login(email: "  READER@example.com  ") }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_login(email: "reader@EXAMPLE.com")

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("auth.alerts.login_rate_limited"))
    expect(counter_keys.join).not_to include("reader@example.com", "READER@example.com", "wrong-password")
  end

  it "counts missing and malformed user params under the blank-email key" do
    4.times { post user_session_path }
    4.times { post user_session_path, params: { user: "malformed" } }

    post user_session_path, params: { user: "malformed" }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "counts different emails separately on the same IP" do
    8.times { attempt_login(email: "first@example.com") }

    attempt_login(email: "second@example.com")

    expect(response).not_to have_http_status(:too_many_requests)
  end

  it "counts the same email separately on different IPs" do
    8.times { attempt_login(email: "reader@example.com", ip: "192.0.2.1") }

    attempt_login(email: "reader@example.com", ip: "192.0.2.2")

    expect(response).not_to have_http_status(:too_many_requests)
  end

  it "counts successful and failed login requests together" do
    user = User.create!(name: "Reader", email: "reader@example.com", password: "password123!")
    attempt_login(email: user.email, password: "password123!")
    expect(response).to redirect_to(root_path)
    delete destroy_user_session_path

    7.times { attempt_login(email: user.email) }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_login(email: user.email)
    expect(response).to have_http_status(:too_many_requests)
  end

  it "keeps the existing suspended-account response and hides its status on rate limiting" do
    user = User.create!(name: "Suspended", email: "suspended@example.com", password: "password123!", suspended_at: Time.current)
    attempt_login(email: user.email, password: "password123!")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("auth.alerts.suspended_fallback"))

    first_attempt_keys = counter_keys.dup
    expect(first_attempt_keys.size).to eq(2)
    ip_key = "rate-limit:users/sessions:login-ip:192.0.2.1"
    expect(first_attempt_keys).to include(ip_key)
    email_key = first_attempt_keys.find { |key| key.start_with?("rate-limit:users/sessions:login-ip-email:") }
    expect(email_key).to be_present
    expect(counter_store.read(ip_key)).to eq(1)
    expect(counter_store.read(email_key)).to eq(1)

    7.times do |index|
      attempt_login(email: user.email)
      expect(counter_keys.size).to eq(2 * (index + 2))
      expect(counter_keys.last(2)).to match_array(first_attempt_keys)
      expect(counter_store.read(ip_key)).to eq(index + 2)
      expect(counter_store.read(email_key)).to eq(index + 2)
    end

    attempt_login(email: user.email)

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).not_to include(I18n.t("auth.alerts.suspended_fallback"))
  end

  it "does not sign in a user while rendering a blocked login attempt" do
    user = User.create!(name: "Reader", email: "blocked@example.com", password: "password123!")
    8.times { attempt_login(email: user.email) }

    attempt_login(email: user.email, password: "password123!")

    expect(response).to have_http_status(:too_many_requests)
    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders localized 429 pages for Turbo login and sign-up requests" do
    I18n.with_locale(:en) do
      8.times { attempt_login(email: "turbo@example.com") }
      attempt_login(email: "turbo@example.com", headers: { "ACCEPT" => "text/vnd.turbo-stream.html, text/html" })

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(I18n.t("auth.alerts.login_rate_limited"))
      expect(response.body).to include(I18n.t("auth.actions.sign_in"))

      60.times { attempt_registration }
      attempt_registration(invitation_token:, user: sign_up_attributes,
                           headers: { "ACCEPT" => "text/vnd.turbo-stream.html, text/html" })

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(form[action="#{user_registration_path}"]))).to be_present
      expect(page.at_css('input[name="user[name]"]')["value"]).to eq(sign_up_attributes[:name])
      expect(page.css('input[type="password"]').map { |field| field["value"] }).to all(be_blank)
      expect(page.text).to include(I18n.t("registration_invitations.password_reentry_notice"))
      expect(invitation.reload.consumed_at).to be_nil
    end
  end

  it "accepts another request after the five-minute window expires" do
    8.times { attempt_login(email: "reader@example.com") }
    attempt_login(email: "reader@example.com")
    expect(response).to have_http_status(:too_many_requests)

    travel_to(5.minutes.from_now + 1.second) do
      attempt_login(email: "reader@example.com")
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
