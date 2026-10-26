require "rails_helper"

RSpec.describe "Password resets", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:reader) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!") }

  def request_reset(email: reader.email, ip: "192.0.2.1", headers: {})
    post user_password_path, params: { user: { email: } }, headers: { "REMOTE_ADDR" => ip }.merge(headers)
  end

  def reset_token_from_mail
    body = ActionMailer::Base.deliveries.last.text_part.body.decoded
    url = body[/https?:\/\/\S+/]
    URI.decode_www_form(URI(url).query).to_h.fetch("reset_password_token")
  end

  def change_password(token, password: "newpassword123!")
    put user_password_path, params: {
      user: { reset_password_token: token, password:, password_confirmation: password }
    }
  end

  it "links the sign-in screen to a reset request and sends a multipart email" do
    get new_user_session_path
    expect(response.body).to include(new_user_password_path, I18n.t("auth.passwords.forgot_password"))

    expect { request_reset(email: "  READER@EXAMPLE.COM  ") }
      .to change(ActionMailer::Base.deliveries, :size).by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(response).to redirect_to(new_user_password_path)
    expect(flash[:notice]).to eq(I18n.t("auth.passwords.request_sent"))
    expect(mail.to).to eq([ reader.email ])
    expect(mail.from).to eq([ "account@jjaek.kr" ])
    expect(mail[:from].decoded).to include("책짹")
    expect(mail.reply_to).to eq([ "support@jjaek.kr" ])
    expect(mail.html_part.body.decoded).to include("reset_password_token=")
    expect(mail.text_part.body.decoded).to include("reset_password_token=")
    parsed_mail = Mail.read_from_string(mail.to_s)
    logo = parsed_mail.attachments["bookjjaek-logo.png"]
    expect(logo).to be_present
    expect(logo.mime_type).to eq("image/png")
    expect(logo.content_disposition).to start_with("inline")
    expect(logo.url).to start_with("cid:")
    expect(logo.body.decoded).to eq(File.binread(Rails.root.join("app/assets/images/logo/logo_black_mini.png")))
    logo_image = Nokogiri::HTML(parsed_mail.html_part.body.decoded).at_css("img[src^='cid:']")
    expect(logo_image).to be_present
    expect(logo_image["src"]).to eq(logo.url)
    expect(logo_image["alt"]).to eq("책짹")
  end

  it "shows the same result for unknown, withdrawn, and active addresses without sending to ineligible accounts" do
    expect { request_reset(email: "missing@example.com") }
      .not_to change(ActionMailer::Base.deliveries, :size)
    unknown_status = response.status
    unknown_notice = flash[:notice]

    expect { request_reset }.to change(ActionMailer::Base.deliveries, :size).by(1)
    expect(response.status).to eq(unknown_status)
    expect(flash[:notice]).to eq(unknown_notice)

    reader.update!(withdrawn_at: Time.current)
    expect { request_reset(email: reader.email) }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(response.status).to eq(unknown_status)
    expect(flash[:notice]).to eq(unknown_notice)
    expect(response.body).not_to include("withdrawn", "탈퇴")
  end

  it "uses an HTTPS reset link when the mailer has production URL options" do
    original_options = UsersMailer.default_url_options
    UsersMailer.default_url_options = { host: "jjaek.kr", protocol: "https" }

    request_reset
    mail = ActionMailer::Base.deliveries.last
    expect(mail.html_part.body.decoded).to include("https://jjaek.kr/users/password/edit?reset_password_token=")
    expect(mail.text_part.body.decoded).to include("https://jjaek.kr/users/password/edit?reset_password_token=")
  ensure
    UsersMailer.default_url_options = original_options
  end

  it "changes a password once and requires a fresh sign-in" do
    request_reset
    token = reset_token_from_mail

    change_password(token)
    expect(response).to be_redirect
    expect(reader.reload.valid_password?("newpassword123!")).to be(true)
    expect(reader.valid_password?("password123!")).to be(false)

    get root_path
    expect(response).to redirect_to(new_user_session_path)

    change_password(token, password: "anotherpassword123!")
    expect(response).to have_http_status(:unprocessable_content)
    expect(reader.reload.valid_password?("anotherpassword123!")).to be(false)

    post user_session_path, params: { user: { email: reader.email, password: "newpassword123!" } }
    expect(response).to redirect_to(root_path)
  end

  it "rejects a reset token after six hours" do
    request_reset
    token = reset_token_from_mail

    travel_to(6.hours.from_now + 1.second) do
      change_password(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(reader.reload.valid_password?("password123!")).to be(true)
    end
  end

  it "shows a Korean validation error when the new passwords do not match" do
    request_reset
    token = reset_token_from_mail

    put user_password_path, params: {
      user: { reset_password_token: token, password: "newpassword123!", password_confirmation: "different123!" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("일치하지 않습니다")
    expect(reader.reload.valid_password?("password123!")).to be(true)
  end

  it "preserves a suspended account and its sign-in restriction after a password change" do
    reader.update!(suspended_at: Time.current)
    request_reset
    token = reset_token_from_mail

    change_password(token)
    expect(response).to be_redirect
    expect(reader.reload).to be_suspended
    expect(reader.valid_password?("newpassword123!")).to be(true)

    post user_session_path, params: { user: { email: reader.email, password: "newpassword123!" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("auth.alerts.suspended_fallback"))
  end

  it "rejects a token that belongs to an account withdrawn after the email was sent" do
    request_reset
    token = reset_token_from_mail
    reader.update!(withdrawn_at: Time.current)

    change_password(token)
    expect(response).to have_http_status(:unprocessable_content)
    expect(reader.reload.valid_password?("password123!")).to be(true)
  end

  context "with a real rate-limit counter" do
    let(:counter_store) { ActiveSupport::Cache::MemoryStore.new }
    let(:counter_keys) { [] }

    before do
      allow(Users::PasswordsController.cache_store).to receive(:increment) do |key, amount, **options|
        counter_keys << key
        counter_store.increment(key, amount, **options)
      end
    end

    it "limits a normalized email and IP pair to three requests without storing the address in a key" do
      3.times { request_reset(email: "  READER@example.com  ") }
      expect(response).not_to have_http_status(:too_many_requests)

      expect { request_reset(email: "reader@EXAMPLE.COM") }
        .not_to change(ActionMailer::Base.deliveries, :size)
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(I18n.t("auth.passwords.rate_limited"))
      expect(counter_keys.join).not_to include(reader.email)

      request_reset(email: reader.email, ip: "192.0.2.2")
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "limits an IP to sixty requests in an hour and gives Turbo the same HTML response" do
      60.times { |index| request_reset(email: "missing-#{index}@example.com") }
      expect(response).not_to have_http_status(:too_many_requests)

      request_reset(email: "another@example.com", headers: { "ACCEPT" => "text/vnd.turbo-stream.html, text/html" })
      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")

      travel_to(1.hour.from_now + 1.second) do
        request_reset(email: "another@example.com")
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end
  end
end
