require "rails_helper"

RSpec.describe "Settings", type: :request do
  include ActiveJob::TestHelper

  let!(:user) { User.create!(name: "Reader", email: "settings-reader@example.com", password: "password123!") }

  def png_upload(index = 1)
    path = Rails.root.join("app/assets/images/avatars/user_profile_#{index.to_s.rjust(2, '0')}_128.png")
    Rack::Test::UploadedFile.new(path, "image/png")
  end

  it "requires sign in" do
    get account_settings_path
    expect(response).to redirect_to(new_user_session_path)

    patch account_settings_path, params: { user: { allows_new_followers: "0" } }
    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.allows_new_followers).to be(true)

    patch avatar_account_settings_path, params: { user: { avatar: png_upload } }
    expect(response).to redirect_to(new_user_session_path)
    delete avatar_account_settings_path
    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.avatar).not_to be_attached
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
    expect(page.at_css("nav a[href='#{account_settings_path}']")).to be_nil
    expect(page.at_css("nav a[href='#{account_relationships_path}']")).to be_nil
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

  it "lets a legacy account set a handle once and keeps invalid input visible" do
    sign_in user

    patch account_settings_path, params: { user: { name: "Unsaved Reader", handle: "invalid-name" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("invalid-name")
    expect(response.body).to include("Unsaved Reader")
    expect(user.reload.handle).to be_nil
    expect(user.name).to eq("Reader")

    patch account_settings_path, params: { user: { name: "Reader", handle: "Reader_One" } }
    expect(response).to redirect_to(account_settings_path)
    expect(user.reload.handle).to eq("reader_one")

    patch account_settings_path, params: { user: { handle: "changed_name" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.handle).to eq("reader_one")
  end

  it "shows handle guidance only while the account has no handle" do
    sign_in user

    get account_settings_path
    expect(response.body).to include(I18n.t("user_handle.guidance"))

    user.update!(handle: "reader_one")
    get account_settings_path
    expect(response.body).not_to include(I18n.t("user_handle.guidance"))
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

  it "uploads an avatar and shows it in settings without changing the existing profile fields" do
    sign_in user

    patch avatar_account_settings_path, params: { user: { avatar: png_upload } }

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload.avatar).to be_attached
    expect(user.name).to eq("Reader")

    get account_settings_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#avatar-settings img")["src"]).to include("/rails/active_storage/representations/")
    expect(page.at_css("#avatar-settings input[type='file'][name='user[avatar]']")).to be_present

    patch account_settings_path, params: { user: { name: "Renamed reader" } }
    expect(response).to redirect_to(account_settings_path)
    expect(user.reload).to have_attributes(name: "Renamed reader")
    expect(user.avatar).to be_attached
  end

  it "replaces the uploaded image and removes the previous attachment" do
    sign_in user
    patch avatar_account_settings_path, params: { user: { avatar: png_upload(1) } }
    first_blob = user.reload.avatar.blob

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      patch avatar_account_settings_path, params: { user: { avatar: png_upload(2) } }
    end

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload.avatar.blob_id).not_to eq(first_blob.id)
    expect(ActiveStorage::Attachment.where(blob_id: first_blob.id)).to be_empty
    expect(ActiveStorage::Blob.exists?(first_blob.id)).to be(false)
  end

  it "keeps the existing image when an SVG replacement is rejected" do
    sign_in user
    patch avatar_account_settings_path, params: { user: { avatar: png_upload } }
    original_blob_id = user.reload.avatar.blob_id
    get account_settings_path
    original_src = Nokogiri::HTML(response.body).at_css("#avatar-settings img")["src"]

    Tempfile.create([ "invalid-avatar", ".svg" ]) do |file|
      file.binmode
      file.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "image/svg+xml")
      patch avatar_account_settings_path, params: { user: { avatar: upload } }
    end

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("activerecord.errors.models.user.attributes.avatar.invalid_format"))
    expect(user.reload.avatar.blob_id).to eq(original_blob_id)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#avatar-settings img")["src"]).to eq(original_src)
    expect(page.at_css("nav a[href='#{user_path(user)}'] img")["src"]).to eq(original_src)
  end

  it "keeps the existing image when storage rejects a replacement upload" do
    sign_in user
    patch avatar_account_settings_path, params: { user: { avatar: png_upload(1) } }
    original_blob_id = user.reload.avatar.blob_id
    original_attachment_id = user.avatar_attachment.id
    get account_settings_path
    original_src = Nokogiri::HTML(response.body).at_css("#avatar-settings img")["src"]
    allow_any_instance_of(ActiveStorage::Blob).to receive(:upload_without_unfurling).and_raise("storage unavailable")

    expect {
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob) do
        patch avatar_account_settings_path, params: { user: { avatar: png_upload(2) } }
      end
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("settings.avatar.upload_failed"))
    expect(user.reload.avatar.blob_id).to eq(original_blob_id)
    expect(user.avatar_attachment.id).to eq(original_attachment_id)
    expect(ActiveStorage::Blob.exists?(original_blob_id)).to be(true)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#avatar-settings img")["src"]).to eq(original_src)
    expect(page.at_css("nav a[href='#{user_path(user)}'] img")["src"]).to eq(original_src)
  end

  it "rejects a damaged replacement before uploading and preserves both displayed avatars" do
    sign_in user
    patch avatar_account_settings_path, params: { user: { avatar: png_upload } }
    original_blob_id = user.reload.avatar.blob_id
    get account_settings_path
    original_src = Nokogiri::HTML(response.body).at_css("#avatar-settings img")["src"]
    expect_any_instance_of(ActiveStorage::Blob).not_to receive(:upload_without_unfurling)

    expect {
      Tempfile.create([ "damaged-avatar", ".png" ]) do |file|
        file.binmode
        png = File.binread(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"))
        file.write(png.byteslice(0, png.bytesize / 2))
        file.flush
        patch avatar_account_settings_path, params: { user: { avatar: Rack::Test::UploadedFile.new(file.path, "image/png") } }
      end
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("activerecord.errors.models.user.attributes.avatar.invalid_format"))
    expect(user.reload.avatar.blob_id).to eq(original_blob_id)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#avatar-settings img")["src"]).to eq(original_src)
    expect(page.at_css("nav a[href='#{user_path(user)}'] img")["src"]).to eq(original_src)
  end

  it "rejects an oversized image without creating an attachment" do
    sign_in user
    Tempfile.create([ "large-avatar", ".png" ]) do |file|
      file.binmode
      file.write(File.binread(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")))
      file.write("x" * (User::MAX_AVATAR_SIZE + 1))
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      patch avatar_account_settings_path, params: { user: { avatar: upload } }
    end

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("activerecord.errors.models.user.attributes.avatar.too_large"))
    expect(user.reload.avatar).not_to be_attached
  end

  it "removes an uploaded image and returns to the assigned default avatar" do
    sign_in user
    patch avatar_account_settings_path, params: { user: { avatar: png_upload } }
    blob_id = user.reload.avatar.blob_id

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      delete avatar_account_settings_path
    end

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload.avatar).not_to be_attached
    expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
    get account_settings_path
    expect(Nokogiri::HTML(response.body).at_css("#avatar-settings img")["src"]).to include("user_profile_#{user.default_avatar_index.to_s.rjust(2, '0')}_128")
  end

  it "changes only the signed-in user's avatar even if another id is submitted" do
    other = User.create!(name: "Other", email: "other-avatar-settings@example.com", password: "password123!")
    sign_in user

    patch avatar_account_settings_path, params: { user: { id: other.id, avatar: png_upload } }

    expect(response).to redirect_to(account_settings_path)
    expect(user.reload.avatar).to be_attached
    expect(other.reload.avatar).not_to be_attached
  end
end
