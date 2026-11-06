require "rails_helper"

RSpec.describe "Book context composition", type: :system do
  include Warden::Test::Helpers
  let(:user) { User.create!(name: "Reader", email: "book-context-system@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Context book") }
  let(:group) { Group.create!(name: "Club", group_admin: user, lifecycle_status: :active) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [1280, 720]
    login_as user, scope: :user
  end
  after { Warden.test_reset! }

  it "keeps the Group destination when the preselected book is removed and the note is saved" do
    visit book_path(book, group_id: group.id)
    within("#book-jjaek-form") do
      expect(page).to have_no_select("jjaek[visibility]")
      fill_in "jjaek[content]", with: "Group note without a book"
      click_button I18n.t("jjaek_books.remove")
      click_button I18n.t("jjaeks.actions.publish_short")
    end
    expect(page).to have_text("Group note without a book")
    record = group.jjaeks.find_by!(content: "Group note without a book")
    expect(record.attached_books).to be_empty
    expect(user.bookshelf_entries).to be_empty
  end
end
