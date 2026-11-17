require "rails_helper"

RSpec.describe "Photo composition and gallery", type: :system do
  include Warden::Test::Helpers

  let(:writer) { User.create!(name: "Photo composer", email: "photo-composer@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Photo selection book") }
  let(:image_path) { Rails.root.join("app/assets/images/avatars/user_profile_01_128.png") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
    login_as writer, scope: :user
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
  end

  after { Warden.test_reset! }

  def choose_photo
    attach_file("jjaek-photo-picker", image_path, make_visible: true)
  end

  def watch_photo_picker
    page.execute_script(<<~JS)
      window.photoPickerClicks = 0
      document.getElementById("jjaek-photo-picker").click = () => { window.photoPickerClicks++ }
    JS
  end

  def expect_draft
    expect(page).to have_field("jjaek[content]", with: "Photo draft #reading")
    expect(page).to have_css("[data-new-photo] img[src^='blob:']", count: 1)
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('jjaek[photo_files][]').filter(file => file.size > 0).length")).to eq(1)
  end

  it "keeps photos and body through book search, cancel, return, Turbo visits and a failed publish" do
    visit root_path
    fill_in "jjaek[content]", with: "Photo draft #reading"
    watch_photo_picker
    click_button I18n.t("jjaek_photos.add")
    within("dialog.jjaek-photo-guidance[open]") do
      click_button I18n.t("jjaek_photos.guidance.confirm")
    end
    expect(page).to have_no_css("dialog.jjaek-photo-guidance[open]")
    expect(page.evaluate_script("window.photoPickerClicks")).to eq(1)
    choose_photo
    expect_draft
    expect(writer.jjaeks).to be_empty

    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      fill_in "book-selection-query", with: book.title
      click_button I18n.t("book_search.form.submit")
    end
    within("#book-selection-search-results article[data-book-id='#{book.id}']") do
      click_button I18n.t("jjaek_books.choose")
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
    end
    within("#book-selection-window") { click_button I18n.t("book_search.actions.close") }
    expect(page).to have_current_path(root_path)
    expect_draft
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key]")

    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      fill_in "book-selection-query", with: book.title
      click_button I18n.t("book_search.form.submit")
    end
    within("#book-selection-search-results article[data-book-id='#{book.id}']") do
      click_button I18n.t("jjaek_books.choose")
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
    end
    within("#book-selection-window") { click_button I18n.t("jjaek_books.finish_selection") }
    expect(page).to have_current_path(root_path)
    expect_draft
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")

    watch_photo_picker
    click_button I18n.t("jjaek_photos.add")
    expect(page).to have_no_css("dialog.jjaek-photo-guidance[open]")
    expect(page.evaluate_script("window.photoPickerClicks")).to eq(1)

    page.execute_script("Turbo.visit(arguments[0])", user_path(writer))
    expect(page).to have_current_path(user_path(writer))
    page.execute_script("Turbo.visit(arguments[0])", root_path)
    expect(page).to have_current_path(root_path)
    expect_draft
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")

    allow(JjaekPhotoUpload).to receive(:enabled?).and_return(false)
    watch_photo_picker
    click_button I18n.t("jjaek_photos.add")
    expect(page).to have_no_css("dialog.jjaek-photo-guidance[open]")
    expect(page.evaluate_script("window.photoPickerClicks")).to eq(1)
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_text(I18n.t("jjaek_photos.disabled"))
    expect(page).to have_css("[data-jjaek-photos-target='error'][role='alert'] [data-photo-error-code='disabled']")
    expect_draft
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")
    expect(writer.jjaeks).to be_empty
    expect(page).to have_no_text(I18n.t("jjaeks.notices.created"))
    within("[data-new-photo='0']") { click_button I18n.t("jjaek_photos.remove"), enable_aria_label: true }
    expect(page).to have_no_css("[data-jjaek-photos-target='error']", visible: true)
    expect(page).to have_field("jjaek[content]", with: "Photo draft #reading")
    choose_photo
    expect_draft
    allow(JjaekPhotoUpload).to receive(:enabled?).and_return(true)
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_text(I18n.t("jjaeks.notices.created"))
    saved = writer.jjaeks.find_by!(content: "Photo draft #reading")
    expect(saved.photos.count).to eq(1)
    expect(saved.attached_books).to eq([ book ])
    page.execute_script("Turbo.visit(arguments[0])", root_path)
    expect(page).to have_current_path(root_path)
    expect(page).to have_field("jjaek[content]", with: "")
    expect(page).to have_no_css("[data-new-photo]")
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key]")
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('jjaek[photo_files][]').filter(file => file.size > 0).length")).to eq(0)
    click_button I18n.t("jjaek_photos.add")
    expect(page).to have_css("dialog.jjaek-photo-guidance[open]")
  end

  it "keeps the draft after an authentication redirect and a Turbo return in the same tab" do
    visit new_jjaek_path(selected_books: [ book.id ])
    fill_in "jjaek[content]", with: "Photo draft #reading"
    choose_photo
    expect_draft
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")

    logout :user
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_current_path(new_user_session_path)
    expect(writer.jjaeks).to be_empty
    expect(page).to have_no_text(I18n.t("jjaeks.notices.created"))

    # Restore authentication without a document reload: A17 drafts live only in
    # this tab's JavaScript memory, including while Turbo displays the login page.
    login_as writer, scope: :user
    page.execute_script("Turbo.visit(arguments[0])", new_jjaek_path)
    expect(page).to have_current_path(new_jjaek_path)
    expect_draft
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{book.id}']")
  end

  it "shows configured guidance once while editing and Cancel only closes the dialog" do
    jjaek = writer.jjaeks.create!(content: "Editing")
    allow(JjaekPhotoUpload).to receive(:daily_limit).and_return(7)
    visit edit_jjaek_path(jjaek)
    expect(page).to have_no_text(I18n.t("jjaek_photos.guidance.privacy"))
    watch_photo_picker
    click_button I18n.t("jjaek_photos.add")
    within("dialog.jjaek-photo-guidance[open]") do
      expect(page).to have_text(I18n.t("jjaek_photos.guidance.privacy"))
      expect(page).to have_text(I18n.t("jjaek_photos.guidance.consent"))
      expect(page).to have_text(I18n.t("jjaek_photos.guidance.limits", daily: 7, per_jjaek: 4))
      expect(page).to have_text("JPEG/PNG/WebP")
      click_button I18n.t("jjaek_photos.guidance.cancel")
    end
    expect(page).to have_no_css("dialog.jjaek-photo-guidance[open]")
    expect(page.evaluate_script("window.photoPickerClicks")).to eq(0)
    expect(page).to have_field("jjaek[content]", with: "Editing")
    expect(jjaek.reload.photos).not_to be_attached
    click_button I18n.t("jjaek_photos.add")
    expect(page).to have_no_css("dialog.jjaek-photo-guidance[open]")
    expect(page.evaluate_script("window.photoPickerClicks")).to eq(1)
  end

  it "preserves valid photos and body through inline size, format and decoding errors" do
    visit root_path
    fill_in "jjaek[content]", with: "Photo draft #reading"
    choose_photo
    expect_draft
    page.execute_script("window.photoAlerts = []; window.alert = message => window.photoAlerts.push(message)")

    Tempfile.create([ "large-photo", ".png" ]) do |file|
      file.truncate(JjaekPhotoChanges::MAX_SIZE + 1)
      file.flush
      attach_file("jjaek-photo-picker", file.path, make_visible: true)
      expect(page).to have_css("[data-jjaek-photos-target='error'][role='alert']", text: I18n.t("jjaek_photos.too_large"))
      expect_draft
    end
    Tempfile.create([ "unsupported-photo", ".svg" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      file.flush
      attach_file("jjaek-photo-picker", file.path, make_visible: true)
      expect(page).to have_css("[data-jjaek-photos-target='error'][role='alert']", text: I18n.t("jjaek_photos.unsupported_format"))
      expect_draft
    end
    Tempfile.create([ "broken-photo", ".png" ]) do |file|
      file.write("not an image")
      file.flush
      attach_file("jjaek-photo-picker", file.path, make_visible: true)
      expect(page).to have_css("[data-jjaek-photos-target='error'][role='alert']", text: I18n.t("jjaek_photos.invalid"))
      expect_draft
    end
    choose_photo
    expect(page).to have_css("[data-new-photo]", count: 2)
    expect(page).to have_no_css("[data-jjaek-photos-target='error']", visible: true)
    expect(page).to have_field("jjaek[content]", with: "Photo draft #reading")
    expect(page.evaluate_script("window.photoAlerts")).to be_empty
  end

  it "enforces four previews, removes individual photos and navigates the gallery on mobile and desktop" do
    visit root_path
    fill_in "jjaek[content]", with: "Gallery"
    4.times do |index|
      choose_photo
      expect(page).to have_css("[data-new-photo]", count: index + 1)
    end
    choose_photo
    expect(page).to have_text(I18n.t("jjaek_photos.limit"))
    within("[data-new-photo='1']") { click_button I18n.t("jjaek_photos.remove"), enable_aria_label: true }
    expect(page).to have_css("[data-new-photo]", count: 3)
    expect(page).to have_no_css("[data-jjaek-photos-target='error']", visible: true)
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('jjaek[photo_files][]').filter(file => file.size > 0).length")).to eq(3)
    choose_photo
    expect(page).to have_css("[data-new-photo]", count: 4)
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_css(".jjaek-photo-grid[data-count='4']")
    click_button I18n.t("jjaek_photos.open", number: 1), enable_aria_label: true
    within("dialog.photo-gallery[open]") do
      expect(page).to have_text("1 / 4")
      expect(find("img")["src"]).to include("size=gallery")
      click_button I18n.t("jjaek_photos.next"), enable_aria_label: true
      expect(page).to have_text("2 / 4")
      click_button I18n.t("jjaek_photos.close"), enable_aria_label: true
    end
    expect(page).to have_no_css("dialog.photo-gallery[open]")
    page.current_window.resize_to(1920, 1080)
    original_overflow = page.evaluate_script("getComputedStyle(document.body).overflow")
    click_button I18n.t("jjaek_photos.open", number: 2), enable_aria_label: true
    viewport_gaps = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector("dialog.photo-gallery[open]").getBoundingClientRect()
        return [rect.left, rect.top, window.innerWidth - rect.right, window.innerHeight - rect.bottom]
      })()
    JS
    expect(viewport_gaps).to all(be_within(1).of(0))
    expect(page.evaluate_script("getComputedStyle(document.body).overflow")).to eq("hidden")
    page.driver.browser.action.send_keys(:arrow_left).perform
    expect(page).to have_css("dialog[open] [data-photo-gallery-target='counter']", text: "1 / 4")
    page.driver.browser.action.send_keys(:arrow_right).perform
    expect(page).to have_css("dialog[open] [data-photo-gallery-target='counter']", text: "2 / 4")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_no_css("dialog.photo-gallery[open]")
    expect(page.evaluate_script("getComputedStyle(document.body).overflow")).to eq(original_overflow)

    saved = writer.jjaeks.find_by!(content: "Gallery")
    visit edit_jjaek_path(saved)
    first_photo = saved.ordered_photos.first
    within("[data-photo-id='#{first_photo.id}']") do
      find_button(I18n.t("jjaek_photos.remove"), enable_aria_label: true).send_keys(:enter)
    end
    expect(page).to have_css("[data-photo-id]:not([hidden])", count: 3)
    expect(page).to have_css("input[name='jjaek[remove_photo_ids][]'][value='#{first_photo.id}']", visible: :all)
    expect(saved.reload.photos.count).to eq(4)

    fill_in "jjaek[content]", with: "Photo draft #reading"
    choose_photo
    expect_draft
    allow(JjaekPhotoUpload).to receive(:enabled?).and_return(false)
    click_button I18n.t("jjaeks.actions.save")
    expect(page).to have_css("[data-jjaek-photos-target='error'][role='alert'] [data-photo-error-code='disabled']")
    expect_draft
    expect(page).to have_css("[data-photo-id='#{first_photo.id}'][hidden]", visible: :all)
    expect(page).to have_css("input[name='jjaek[remove_photo_ids][]'][value='#{first_photo.id}']", visible: :all)
    expect(saved.reload.content).to eq("Gallery")
    expect(saved.photos.count).to eq(4)
    find("main a[data-back-link]").click
    expect(page).to have_no_current_path(edit_jjaek_path(saved), ignore_query: true)
    expect(saved.reload.photos.count).to eq(4)
  end
end
