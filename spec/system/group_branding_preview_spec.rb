require "rails_helper"

RSpec.describe "Group branding preview", type: :system do
  include Warden::Test::Helpers

  let(:admin) { User.create!(name: "Preview admin", email: "group-preview-admin@example.com", password: "password123!") }
  let(:group) { Group.create!(group_admin: admin, name: "Preview readers", lifecycle_status: :active) }
  let(:first_image) { Rails.root.join("app/assets/images/avatars/user_profile_01_128.png") }
  let(:second_image) { Rails.root.join("app/assets/images/avatars/user_profile_02_128.png") }

  before do
    driven_by :selenium, using: :headless_chrome
    login_as admin, scope: :user
  end

  after do
    Warden.test_reset!
    ActiveStorage::Blob.where("metadata::jsonb @> ?", { group_image: true, group_id: group.id }.to_json).find_each do |blob|
      blob.variant_records.each { |variant| variant.image.blob.delete if variant.image.attached? }
      blob.delete
    end
  end

  it "previews both files, cancels selections, and defers saved image removal until a successful submission" do
    visit edit_group_path(group)
    expect(page).to have_text(I18n.t("groups.branding.title"))
    %w[profile_image cover_image].each do |name|
      attach_file("group[#{name}_file]", first_image)
      field = find("input[name='group[#{name}_file]']").find(:xpath, "..")
      expect(field.find("img")["src"]).to start_with("blob:")
    end
    expect(group.reload.profile_image).not_to be_attached
    expect(group.cover_image).not_to be_attached
    within("#group-branding-form") { click_button I18n.t("groups.actions.update") }
    expect(page).to have_current_path(group_path(group))
    group.reload
    saved_ids = Group::IMAGE_NAMES.to_h { |name| [ name, group.public_send("#{name}_attachment").id ] }

    visit edit_group_path(group)
    page.execute_script(<<~JS)
      window.revokedGroupPreviewUrls = []
      const revoke = URL.revokeObjectURL.bind(URL)
      URL.revokeObjectURL = url => { window.revokedGroupPreviewUrls.push(url); revoke(url) }
    JS
    Group::IMAGE_NAMES.each do |name|
      field = find("input[name='group[#{name}_file]']").find(:xpath, "..")
      saved_source = field.find("img")["src"]
      image_label = I18n.t("groups.branding.#{name}")
      remove_label = I18n.t("groups.branding.remove_image", image: image_label)
      cancel_label = I18n.t("groups.branding.cancel_selection", image: image_label)
      remove_button = "button:enabled[data-group-image-preview-target='removeButton'][aria-label='#{remove_label}']"
      cancel_button = "button:enabled[data-group-image-preview-target='removeButton'][aria-label='#{cancel_label}']"
      attach_file("group[#{name}_file]", second_image)
      expect(field).to have_css("img[src^='blob:']")
      preview_url = field.find("img")["src"]
      field.find(cancel_button, visible: true).click
      expect(field.find("img")["src"]).to eq(saved_source)
      expect(field.find("input[type='file']").value).to eq("")
      expect(page.evaluate_script("window.revokedGroupPreviewUrls")).to include(preview_url)

      field.find(remove_button, visible: true).send_keys(:enter)
      expect(field).to have_text(I18n.t("groups.branding.removal_pending"))
      expect(field.find("input[name='group[remove_#{name}]']", visible: false).value).to eq("1")
      expect(group.reload.public_send("#{name}_attachment").id).to eq(saved_ids.fetch(name))
      attach_file("group[#{name}_file]", second_image)
      expect(field.find("input[name='group[remove_#{name}]']", visible: false).value).to eq("0")
      expect(field).to have_no_text(I18n.t("groups.branding.removal_pending"))
      field.find(cancel_button, visible: true).click
      field.find(remove_button, visible: true).click
      field.click_button I18n.t("groups.branding.undo_removal")
      expect(field.find("img")["src"]).to eq(saved_source)
      field.find(remove_button, visible: true).click
    end

    fill_in "group[name]", with: "Unsubmitted name"
    page.execute_script(<<~JS)
      const color = document.querySelector('#group-branding-form input[name="group[brand_color]"]')
      color.value = 'invalid'
      color.checked = true
    JS
    within("#group-branding-form") { click_button I18n.t("groups.actions.update") }
    expect(page).to have_css("#group-branding-form [role='alert']")
    expect(page).to have_no_css("#group-information-form [role='alert']")
    expect(group.reload.name).to eq("Preview readers")
    Group::IMAGE_NAMES.each do |name|
      expect(group.reload.public_send("#{name}_attachment").id).to eq(saved_ids.fetch(name))
      expect(page).to have_css("img[src*='/images/#{saved_ids.fetch(name)}?']")
    end

    fill_in "group[name]", with: group.name
    profile_remove_button = "button:enabled[data-group-image-preview-target='removeButton'][aria-label='#{I18n.t("groups.branding.remove_image", image: I18n.t("groups.branding.profile_image"))}']"
    find(profile_remove_button, visible: true).click
    attach_file("group[cover_image_file]", second_image)
    preview_url = find("img[src^='blob:']")["src"]
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    expect(page).to have_no_css("img[src^='blob:']")
    expect(find("input[name='group[remove_profile_image]']", visible: false).value).to eq("0")
    expect(page.evaluate_script("window.revokedGroupPreviewUrls")).to include(preview_url)
    find(profile_remove_button, visible: true).click
    within("#group-branding-form") { click_button I18n.t("groups.actions.update") }
    expect(page).to have_current_path(group_path(group))
    expect(group.reload.profile_image).not_to be_attached
    expect(group.cover_image_attachment.id).to eq(saved_ids.fetch("cover_image"))
  end
end
