require "rails_helper"

RSpec.describe "Registration invitations", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:admin) { User.create!(name: "Admin", email: "invite-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Reader", email: "reader@example.com", password: "password123!") }

  def issue_invitation(email = "new-reader@example.com")
    invitation = RegistrationInvitation.new(email:, invited_by: admin)
    token = invitation.issue_token!
    invitation.save!
    [ invitation, token ]
  end

  def registration_attributes(email = "new-reader@example.com")
    { name: "New Reader", handle: "new_reader", email:, password: "password123!", password_confirmation: "password123!" }
  end

  def delivered_token
    mail = ActionMailer::Base.deliveries.last
    url = mail.text_part.body.decoded[/https?:\/\/\S+/]
    URI.decode_www_form(URI(url).query).to_h.fetch("invitation_token")
  end

  it "restricts invitation management to a global admin" do
    invitation, = issue_invitation("protected@example.com")
    get admin_registration_invitations_path
    expect(response).to redirect_to(new_user_session_path)
    post resend_admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(new_user_session_path)
    delete admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(new_user_session_path)
    post admin_registration_invitations_path, params: { registration_invitation: { email: "blocked@example.com" } }
    expect(response).to redirect_to(new_user_session_path)

    sign_in reader
    get admin_registration_invitations_path
    expect(response).to redirect_to(root_path)
    post resend_admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(root_path)
    delete admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(root_path)
    expect(invitation.reload.canceled_at).to be_nil
    expect {
      post admin_registration_invitations_path, params: { registration_invitation: { email: "blocked@example.com" } }
    }.not_to change(RegistrationInvitation, :count)
    expect(response).to redirect_to(root_path)

    sign_in admin
    get admin_registration_invitations_path
    expect(response).to have_http_status(:ok)
  end

  it "sends an email while storing only the token digest and normalized address" do
    sign_in admin

    expect {
      post admin_registration_invitations_path, params: { registration_invitation: { email: "  NEW@Example.COM  " } }
    }.to change(RegistrationInvitation, :count).by(1)

    invitation = RegistrationInvitation.last
    mail = ActionMailer::Base.deliveries.last
    token = delivered_token
    expect(invitation.email).to eq("new@example.com")
    expect(invitation.token_digest).to eq(RegistrationInvitation.digest(token))
    expect(invitation.token_digest).not_to eq(token)
    expect(mail.to).to eq([ "new@example.com" ])
    expect(mail.from).to eq([ "account@jjaek.kr" ])
    expect(mail[:from].decoded).to include("책짹")
    expect(mail.reply_to).to eq([ "support@jjaek.kr" ])
    expect(mail.html_part.body.decoded).to include("invitation_token=")
    expect(mail.text_part.body.decoded).to include("invitation_token=")
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
    expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
    korean_expiry = I18n.l(invitation.expires_at.in_time_zone("Asia/Seoul"), locale: :ko, format: :long)
    expect(korean_expiry).to match(/\A\d{4}년 \d{1,2}월 \d{1,2}일 \d{2}:\d{2}\z/)
    expect(parsed_mail.html_part.body.decoded.force_encoding(Encoding::UTF_8)).to include(korean_expiry)
    expect(parsed_mail.text_part.body.decoded.force_encoding(Encoding::UTF_8)).to include(korean_expiry)

    post admin_registration_invitations_path, params: { registration_invitation: { email: "new@example.com" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(RegistrationInvitation.where(email: "new@example.com").count).to eq(1)

    post admin_registration_invitations_path, params: { registration_invitation: { email: reader.email } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not report a successful send when mail delivery raises" do
    sign_in admin
    delivery = double("mail delivery")
    allow(delivery).to receive(:deliver_now).and_raise(StandardError, "SMTP unavailable")
    allow(RegistrationInvitationMailer).to receive(:invite).and_return(delivery)

    expect {
      post admin_registration_invitations_path, params: { registration_invitation: { email: "failure@example.com" } }
    }.to raise_error(StandardError, "SMTP unavailable")
  end

  it "uses an HTTPS registration link when the mailer has production URL options" do
    invitation, token = issue_invitation
    original_options = RegistrationInvitationMailer.default_url_options
    RegistrationInvitationMailer.default_url_options = { host: "jjaek.kr", protocol: "https" }

    mail = RegistrationInvitationMailer.invite(invitation, token).deliver_now
    expect(mail.html_part.body.decoded).to include("https://jjaek.kr/users/sign_up?invitation_token=")
    expect(mail.text_part.body.decoded).to include("https://jjaek.kr/users/sign_up?invitation_token=")
  ensure
    RegistrationInvitationMailer.default_url_options = original_options
  end

  it "invalidates the old link on resend and both links on cancel" do
    invitation, old_token = issue_invitation
    sign_in admin

    post resend_admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(admin_registration_invitations_path)
    expect(RegistrationInvitation.find_by_token(old_token)).to be_nil
    new_token = delivered_token
    new_digest = invitation.reload.token_digest

    delete admin_registration_invitation_path(invitation)
    expect(response).to redirect_to(admin_registration_invitations_path)
    expect(invitation.reload).to have_attributes(canceled_at: be_present)
    expect(invitation.token_digest).to eq(new_digest)
    sign_out admin
    get new_user_registration_path(invitation_token: old_token)
    expect(response).to redirect_to(new_user_session_path)
    get new_user_registration_path(invitation_token: new_token)
    expect(response).to redirect_to(new_user_session_path)

    sign_in admin
    expect {
      post admin_registration_invitations_path, params: { registration_invitation: { email: invitation.email } }
    }.to change(RegistrationInvitation, :count).by(1)
  end

  it "blocks missing, expired, consumed and canceled links" do
    invitation, token = issue_invitation
    post user_registration_path, params: { user: registration_attributes }
    expect(response).to have_http_status(:forbidden)
    expect(User.find_by(email: "new-reader@example.com")).to be_nil

    travel_to 8.days.from_now do
      get new_user_registration_path(invitation_token: token)
      expect(response).to redirect_to(new_user_session_path)
      post user_registration_path, params: { invitation_token: token, user: registration_attributes }
      expect(response).to have_http_status(:forbidden)
    end

    invitation.update!(canceled_at: Time.current)
    post user_registration_path, params: { invitation_token: token, user: registration_attributes }
    expect(response).to have_http_status(:forbidden)
  end

  it "binds the account email to the invitation and consumes it with the user" do
    invitation, token = issue_invitation
    get new_user_registration_path(invitation_token: token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("new-reader@example.com")

    expect {
      post user_registration_path, params: { invitation_token: token, user: registration_attributes("spoof@example.com").merge(global_admin: true) }
    }.to change(User, :count).by(1)
    expect(response).to redirect_to(root_path)
    user = User.find_by!(email: "new-reader@example.com")
    expect(user).not_to be_global_admin
    expect(User.exists?(email: "spoof@example.com")).to be(false)
    expect(invitation.reload.user).to eq(user)
    expect(invitation.consumed_at).to be_present

    sign_out user
    post user_registration_path, params: { invitation_token: token, user: registration_attributes }
    expect(response).to have_http_status(:forbidden)
  end

  it "does not allow a signed-in admin to register another user" do
    invitation, token = issue_invitation
    sign_in admin

    expect {
      post user_registration_path, params: { invitation_token: token, user: registration_attributes }
    }.not_to change(User, :count)
    expect(invitation.reload.consumed_at).to be_nil
  end

  it "preserves the invitation when User validation fails or the address already belongs to a member" do
    invitation, token = issue_invitation
    post user_registration_path, params: { invitation_token: token, user: registration_attributes.merge(handle: "") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(invitation.reload.consumed_at).to be_nil

    invitation.update!(email: reader.email)
    post user_registration_path, params: { invitation_token: token, user: registration_attributes }
    expect(response).to have_http_status(:unprocessable_content)
    expect(invitation.reload.consumed_at).to be_nil
  end

  it "keeps existing member login available" do
    post user_session_path, params: { user: { email: reader.email, password: "password123!" } }
    expect(response).to redirect_to(root_path)
  end
end
