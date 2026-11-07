require "rails_helper"

RSpec.describe "Remember me", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "password123!" }
  let(:user) { User.create!(name: "Remembered reader", email: "remember-reader@example.com", password:) }

  def remember_cookie_header(current_response = response)
    Array(current_response.headers["Set-Cookie"]).flat_map { |value| value.to_s.split("\n") }
      .find { |cookie| cookie.start_with?("remember_user_token=") }
  end

  it "shows an unchecked remember-me checkbox with a localized label" do
    { ko: "로그인 상태 유지", en: "Remember me" }.each do |locale, label|
      I18n.with_locale(locale) do
        get new_user_session_path
        page = Nokogiri::HTML(response.body)
        checkbox = page.at_css("input[type='checkbox'][name='user[remember_me]']")
        expect(checkbox["checked"]).to be_nil
        expect(checkbox["value"]).to eq("1")
        expect(page.at_css("label[for='#{checkbox['id']}']").text).to eq(label)
      end
    end
  end

  [ nil, "0" ].each do |remember_me|
    it "does not issue a persistent cookie when remember_me is #{remember_me.inspect}" do
      credentials = { email: user.email, password: }
      credentials[:remember_me] = remember_me unless remember_me.nil?

      post user_session_path, params: { user: credentials }

      expect(response).to redirect_to(root_path)
      expect(remember_cookie_header).to be_nil
      expect(user.reload.remember_created_at).to be_nil
      restarted_browser = ActionDispatch::Integration::Session.new(Rails.application)
      restarted_browser.get(new_user_session_path)
      expect(restarted_browser.response).to have_http_status(:ok)
    end
  end

  it "restores authentication from the cookie for up to 30 days without extending it" do
    started_at = Time.current
    post user_session_path, params: { user: { email: user.email, password:, remember_me: "1" } }

    expect(response).to redirect_to(root_path)
    cookie = remember_cookie_header
    expect(cookie).to be_present
    expires_at = Time.httpdate(cookie.match(/expires=([^;]+)/i)[1])
    expect(expires_at).to be_between(started_at + 30.days - 1.second, Time.current + 30.days)
    expect(cookie).to match(/;\s*httponly(?:;|\z)/i)
    expect(cookie).to match(/;\s*samesite=lax(?:;|\z)/i)
    expect(user.reload.remember_created_at).to be_present
    cookie_pair = cookie.split(";", 2).first

    travel_to(29.days.from_now) do
      restarted_browser = ActionDispatch::Integration::Session.new(Rails.application)
      restarted_browser.get(notifications_path, headers: { "Cookie" => cookie_pair })
      expect(restarted_browser.response).to have_http_status(:ok)
      expect(remember_cookie_header(restarted_browser.response)).to be_nil
    end

    travel_to(31.days.from_now) do
      expired_browser = ActionDispatch::Integration::Session.new(Rails.application)
      expired_browser.get(new_user_session_path, headers: { "Cookie" => cookie_pair })
      expect(expired_browser.response).to have_http_status(:ok)
    end
  end

  it "invalidates the saved remember cookie on sign out" do
    post user_session_path, params: { user: { email: user.email, password:, remember_me: "1" } }
    cookie_pair = remember_cookie_header.split(";", 2).first

    delete destroy_user_session_path

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.remember_created_at).to be_nil
    replayed_browser = ActionDispatch::Integration::Session.new(Rails.application)
    replayed_browser.get(root_path, headers: { "Cookie" => cookie_pair })
    expect(replayed_browser.response).to redirect_to(new_user_session_path)
  end

  it "does not restore or remember a withdrawn account" do
    credentials = { email: user.email, password:, remember_me: "1" }
    post user_session_path, params: { user: credentials }
    cookie_pair = remember_cookie_header.split(";", 2).first
    user.update!(withdrawn_at: Time.current)

    restarted_browser = ActionDispatch::Integration::Session.new(Rails.application)
    restarted_browser.get(new_user_session_path, headers: { "Cookie" => cookie_pair })
    expect(restarted_browser.response).to have_http_status(:ok)

    login_browser = ActionDispatch::Integration::Session.new(Rails.application)
    login_browser.post(user_session_path, params: { user: credentials })
    expect(remember_cookie_header(login_browser.response)).to be_nil
    login_browser.get(new_user_session_path)
    expect(login_browser.response).to have_http_status(:ok)
    login_browser.get(notifications_path)
    expect(login_browser.response).not_to have_http_status(:ok)
  end
end
