require "rails_helper"

RSpec.describe "Password settings", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "password-settings@example.com", password: "password123!") }
  let(:password_attributes) do
    { current_password: "password123!", password: "newpassword123!", password_confirmation: "newpassword123!" }
  end

  it "provides a separate password form with appropriate autocomplete fields" do
    sign_in user
    get account_settings_path

    page = Nokogiri::HTML(response.body)
    form = page.at_css("form[action='#{password_account_settings_path}']")
    expect(form).to be_present
    expect(form.at_css("input[name='user[current_password]'][type='password'][autocomplete='current-password']")).to be_present
    %w[password password_confirmation].each do |field|
      expect(form.at_css("input[name='user[#{field}]'][type='password'][autocomplete='new-password']")).to be_present
    end
    expect(form.at_css("input[name='user[name]']")).to be_nil
    expect(form.at_css("input[name='user[allows_new_followers]']")).to be_nil
  end

  it "requires sign in without changing the password" do
    expect {
      patch password_account_settings_path, params: { user: password_attributes }
    }.not_to change { user.reload.encrypted_password }

    expect(response).to redirect_to(new_user_session_path)
  end

  {
    "HTML" => {},
    "Turbo" => { "ACCEPT" => "text/vnd.turbo-stream.html, text/html" }
  }.each do |format, headers|
    context "with #{format} requests" do
      it "changes the password without email, signs out, and requires the new password for sign in" do
        post user_session_path, params: { user: { email: user.email, password: "password123!", remember_me: "1" } }
        expect(response).to redirect_to(root_path)

        expect {
          patch password_account_settings_path, params: { user: password_attributes }, headers:
        }.not_to change(ActionMailer::Base.deliveries, :size)

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to eq(I18n.t("devise.passwords.updated"))
        expect(user.reload.valid_password?("password123!")).to be(false)
        expect(user.valid_password?("newpassword123!")).to be(true)
        follow_redirect!
        expect(response.body).to include(I18n.t("devise.passwords.updated"))
        expect(response.body).not_to include("password123!", "newpassword123!")

        get account_settings_path
        expect(response).to redirect_to(new_user_session_path)

        post user_session_path, params: { user: { email: user.email, password: "password123!" } }
        expect(response).to have_http_status(:unprocessable_content)
        post user_session_path, params: { user: { email: user.email, password: "newpassword123!" } }
        expect(response).to redirect_to(root_path)
        get account_settings_path
        expect(response).to have_http_status(:ok)
      end

      it "rejects an incorrect current password, clears inputs, and preserves the session" do
        sign_in user

        expect {
          patch password_account_settings_path,
                params: { user: password_attributes.merge(current_password: "wrongpassword123!") }, headers:
        }.not_to change { user.reload.encrypted_password }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/html")
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("#password-settings [role='alert']").text).to include(
          I18n.t("activerecord.errors.models.user.attributes.current_password.invalid")
        )
        expect(page.css("#password-settings input[type='password']").map { |input| input["value"].to_s }).to eq([ "", "", "" ])
        expect(response.body).not_to include("wrongpassword123!", "password123!", "newpassword123!", user.encrypted_password)
        expect(request.filtered_parameters.fetch("user").values).to all(eq("[FILTERED]"))
        expect(user.valid_password?("password123!")).to be(true)

        get account_settings_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  {
    "missing current password" => [ :current_password, nil, "current_password.blank" ],
    "blank new password" => [ :password, "", "password.blank" ],
    "missing new password" => [ :password, nil, "password.blank" ],
    "mismatched confirmation" => [ :password_confirmation, "different123!", "password_confirmation.confirmation" ],
    "blank confirmation" => [ :password_confirmation, "", "password_confirmation.confirmation" ],
    "missing confirmation" => [ :password_confirmation, nil, "password_confirmation.confirmation" ],
    "short new password" => [ :password, "a" * (Devise.password_length.min - 1), "password.too_short" ],
    "long new password" => [ :password, "a" * (Devise.password_length.max + 1), "password.too_long" ]
  }.each do |scenario, (field, value, error)|
    it "rejects #{scenario} without changing the password or signing out" do
      sign_in user
      attributes = password_attributes.merge(field => value)
      attributes.delete(field) if value.nil?
      attributes[:password_confirmation] = value if field == :password && value.present?

      expect {
        patch password_account_settings_path, params: { user: attributes }
      }.not_to change { user.reload.encrypted_password }

      expect(response).to have_http_status(:unprocessable_content)
      count = error.end_with?("too_short") ? Devise.password_length.min : Devise.password_length.max
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#password-settings [role='alert']").text).to include(
        I18n.t("activerecord.errors.models.user.attributes.#{error}", count:)
      )
      expect(page.css("#password-settings input[type='password']").map { |input| input["value"].to_s }).to eq([ "", "", "" ])
      expect(user.valid_password?("password123!")).to be(true)

      get account_settings_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "changes only the signed-in user's password and ignores unrelated attributes" do
    other = User.create!(name: "Other", email: "other-password-settings@example.com", password: "password123!")
    sign_in user

    patch password_account_settings_path, params: {
      user: password_attributes.merge(id: other.id, name: "Changed", email: other.email, allows_new_followers: "0")
    }

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload).to have_attributes(name: "Reader", email: "password-settings@example.com", allows_new_followers: true)
    expect(user.valid_password?("newpassword123!")).to be(true)
    expect(other.reload.valid_password?("password123!")).to be(true)
  end

  it "ignores password attributes submitted through the profile and relationship settings endpoint" do
    sign_in user

    expect {
      patch account_settings_path, params: { user: password_attributes.merge(name: "Updated Reader", allows_new_followers: "0") }
    }.not_to change { user.reload.encrypted_password }

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload).to have_attributes(name: "Updated Reader", allows_new_followers: false)
    get account_settings_path
    expect(response).to have_http_status(:ok)
  end
end
