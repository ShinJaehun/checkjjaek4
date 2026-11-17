require "rails_helper"

RSpec.describe "Avatar preview", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Avatar reader", email: "avatar-preview@example.com", password: "password123!") }
  let(:first_image) { Rails.root.join("app/assets/images/avatars/user_profile_01_128.png") }
  let(:second_image) { Rails.root.join("app/assets/images/avatars/user_profile_02_128.png") }
  let(:remove_button_selector) { "button:enabled[data-avatar-preview-target='removeButton'][aria-label='#{I18n.t("settings.avatar.remove")}']" }
  let(:cancel_button_selector) { "button:enabled[data-avatar-preview-target='removeButton'][aria-label='#{I18n.t("settings.avatar.cancel_selection")}']" }

  before do
    driven_by :selenium, using: :headless_chrome
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "previews a selected image without uploading it until Save image is pressed" do
    visit account_settings_path
    saved_source = find("#avatar-settings img")["src"]
    expect(page).to have_no_css(remove_button_selector, visible: true)

    click_button I18n.t("settings.avatar.save")
    expect(page).to have_css("#avatar-settings [role='alert']", text: I18n.t("activerecord.errors.models.user.attributes.avatar.blank"))
    expect(page).to have_no_css("#profile-settings [role='alert']")

    attach_file("user[avatar]", first_image)

    expect(find("#avatar-settings img")["src"]).to start_with("blob:")
    expect(page).to have_css("[data-avatar-preview-target='status']", text: I18n.t("settings.avatar.preview_pending"), visible: true)
    expect(user.reload.avatar).not_to be_attached
    expect(page).to have_css(cancel_button_selector, visible: true)

    click_button I18n.t("settings.avatar.save")

    expect(page).to have_current_path(account_settings_path)
    expect(page).to have_css("#avatar-settings img[src*='/users/#{user.id}/avatar_image']")
    expect(user.reload.avatar).to be_attached
    expect(find("#avatar-settings img")["src"]).not_to eq(saved_source)
    expect(page).to have_no_css("[data-avatar-preview-target='status']", visible: true)
    expect(page).to have_css(remove_button_selector, visible: true)
  end

  it "releases temporary URLs and restores the saved image for invalid files, cancel, and page exit" do
    File.open(first_image) do |file|
      user.avatar.attach(io: file, filename: "saved.png", content_type: "image/png")
    end
    saved_blob_id = user.avatar.blob_id
    visit account_settings_path
    saved_source = find("#avatar-settings img")["src"]
    page.execute_script(<<~JS)
      window.revokedAvatarUrls = []
      const revokeObjectURL = URL.revokeObjectURL.bind(URL)
      URL.revokeObjectURL = (url) => {
        window.revokedAvatarUrls.push(url)
        revokeObjectURL(url)
      }
      window.avatarSubmissions = []
      document.addEventListener('turbo:submit-start', event => {
        const form = event.target
        if (new URL(form.action).pathname === #{avatar_account_settings_path.to_json}) {
          window.avatarSubmissions.push(form.querySelector('input[name="_method"]')?.value || form.method)
        }
      })
    JS

    attach_file("user[avatar]", first_image)
    first_preview = find("#avatar-settings img")["src"]
    attach_file("user[avatar]", second_image)
    second_preview = find("#avatar-settings img")["src"]
    expect(second_preview).to start_with("blob:")
    expect(second_preview).not_to eq(first_preview)
    expect(page.evaluate_script("window.revokedAvatarUrls")).to include(first_preview)

    Tempfile.create([ "invalid-avatar", ".svg" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      file.flush
      attach_file("user[avatar]", file.path)
    end
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)
    expect(page).to have_css("[data-avatar-preview-target='error']", visible: true)
    expect(page.evaluate_script("window.revokedAvatarUrls")).to include(second_preview)

    Tempfile.create([ "large-avatar", ".png" ]) do |file|
      file.binmode
      file.write(File.binread(first_image))
      file.write("x" * (User::MAX_AVATAR_SIZE + 1))
      file.flush
      attach_file("user[avatar]", file.path)
    end
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)
    expect(page).to have_css("[data-avatar-preview-target='error']", visible: true)

    Tempfile.create([ "broken-avatar", ".png" ]) do |file|
      file.write("not an image")
      file.flush
      attach_file("user[avatar]", file.path)
    end
    expect(page).to have_css("[data-avatar-preview-target='error']", visible: true)
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)

    attach_file("user[avatar]", first_image)
    third_preview = find("#avatar-settings img")["src"]
    page.execute_script("document.querySelector('#avatar-settings input[type=file]').dispatchEvent(new Event('cancel', { bubbles: true }))")
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)
    expect(page.evaluate_script("window.revokedAvatarUrls")).to include(third_preview)

    attach_file("user[avatar]", first_image)
    final_preview = find("#avatar-settings img")["src"]
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)
    expect(page.evaluate_script("window.revokedAvatarUrls")).to include(final_preview)
    expect(user.reload.avatar).to be_attached
    expect(user.avatar.blob_id).to eq(saved_blob_id)

    attach_file("user[avatar]", second_image)
    cancelled_preview = find("#avatar-settings img")["src"]
    find(cancel_button_selector, visible: true).send_keys(:enter)
    expect(find("#avatar-settings img")["src"]).to eq(saved_source)
    expect(find("#avatar-settings input[type='file']").value).to eq("")
    expect(user.reload.avatar.blob_id).to eq(saved_blob_id)
    expect(page.evaluate_script("window.revokedAvatarUrls")).to include(cancelled_preview)
    expect(page.evaluate_script("window.avatarSubmissions")).to eq([])
    expect(page).to have_no_css("#profile-settings [role='alert'], #avatar-settings [role='alert']")

    find(remove_button_selector, visible: true).send_keys(:enter)
    expect(page).to have_text(I18n.t("settings.avatar.removed"))
    expect(user.reload.avatar).not_to be_attached
    expect(page).to have_no_css(remove_button_selector, visible: true)
    expect(page.evaluate_script("window.avatarSubmissions")).to eq([ "delete" ])
    expect(page).to have_css("#avatar-settings img[src*='user_profile_']")
    expect(page).to have_no_css("#profile-settings [role='alert'], #avatar-settings [role='alert']")
  end
end
