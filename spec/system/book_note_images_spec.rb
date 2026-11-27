require "rails_helper"

RSpec.describe "Images in the reading note editor", type: :system do
  include Warden::Test::Helpers

  let(:reader) { User.create!(name: "Reader", email: "note-editor-images@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "A book with images") }
  let!(:entry) { reader.bookshelf_entries.create!(book:) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
    login_as reader, scope: :user
  end

  after do
    BookNoteImage.where(user: reader).includes(:blob).find_each { |image| image.blob.service.delete(image.blob.key) }
    Warden.test_reset!
  end

  it "inserts an uploaded image at the cursor and keeps it when an edit is cancelled" do
    visit book_path(book, tab: "reading")
    click_button I18n.t("book_notes.new")
    within("#book-note-editor[open]") do
      fill_in I18n.t("book_notes.title"), with: "An illustrated note"
      editor = find("trix-editor")
      editor.click
      editor.send_keys("Before imageAfter image")
      page.execute_script("arguments[0].editor.setSelectedRange(12)", editor)
      expect(page).to have_button(I18n.t("book_notes.add_image"))
      attach_file("book-note-image-picker", Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"), make_visible: true)
      expect(page).to have_css("trix-editor figure img[src*='/book_note_images/']")
      click_button I18n.t("book_notes.save")
    end

    find("#book-notes a", text: "An illustrated note").click
    expect(page).to have_css(".book-note-body img[src*='/book_note_images/']")
    note = entry.user_book.book_notes.sole
    expect(note.editable_body.to_html).to match(/Before image.*book-note-image-id.*After image/m)

    click_button I18n.t("book_notes.edit")
    within("#book-note-editor[open]") do
      find("trix-editor figure img").click
      find("trix-editor figure.attachment img").click
      find("trix-editor button[data-trix-action='remove']").click
      expect(page).to have_no_css("trix-editor figure img")
      accept_confirm(I18n.t("book_notes.confirm_discard")) { click_button I18n.t("book_notes.cancel") }
    end
    expect(page).to have_css(".book-note-body img[src*='/book_note_images/']")
    expect(note.reload.book_note_images.sole).to be_attached
  end
end
