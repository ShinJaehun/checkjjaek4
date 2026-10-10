require "rails_helper"

RSpec.describe "Authentication rate limits", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:counter_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:counter_keys) { [] }

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

  def attempt_registration(headers: {})
    post user_registration_path, params: { user: { name: "Reader", email: "reader@example.com" } }, headers:
  end

  it "allows 60 sign-up requests from one IP and rejects the 61st" do
    60.times { attempt_registration }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_registration

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
    expect(response.body).to include(I18n.t("auth.registrations.title"))
  end

  it "allows 120 login attempts from one IP across distinct emails and rejects the next" do
    120.times { |index| attempt_login(email: "missing-#{index}@example.com") }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_login(email: "another-missing@example.com")

    expect(response).to have_http_status(:too_many_requests)
  end

  it "limits an IP and normalized email combination to eight attempts" do
    8.times { attempt_login(email: "  READER@example.com  ") }
    expect(response).not_to have_http_status(:too_many_requests)

    attempt_login(email: "reader@EXAMPLE.com")

    expect(response).to have_http_status(:too_many_requests)
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
      expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
      expect(response.body).to include(I18n.t("auth.sessions.title"))

      60.times { attempt_registration }
      attempt_registration(headers: { "ACCEPT" => "text/vnd.turbo-stream.html, text/html" })

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(I18n.t("auth.alerts.rate_limited"))
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
