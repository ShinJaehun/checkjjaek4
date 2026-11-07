require "rails_helper"

RSpec.describe "Unified inline composition", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Reader", email: "inline-composer@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Search attachment first", thumbnail: "https://example.com/first-cover.jpg") }
  let!(:other_book) { Book.create!(title: "Search attachment second", thumbnail: "https://example.com/second-cover.jpg") }
  let!(:recommendation) do
    record = build_jjaek_with_books(legacy_source_kind: "recommendation", user: user, content: "Original recommendation")
    record.jjaek_book_attachments.build(book:, position: 0)
    record.save!
    record
  end

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 720 ]
    login_as user, scope: :user
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
  end

  after { Warden.test_reset! }

  it "keeps the draft and visibility through page searches, selection, registration and removal" do
    page.current_window.resize_to(390, 844)
    shelf = user.bookshelves.create!(name: "Chosen shelf")
    visit root_path
    fill_in "jjaek[content]", with: "My draft survives"
    choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true
    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      expect(page).to have_no_field("jjaek[content]")
      fill_in "book-selection-query", with: "Search attachment"
      click_button I18n.t("book_search.form.submit")
    end
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    within("#book-selection-search-results") do
      expect(page).to have_text(book.title)
      [ book, other_book ].each do |selected_book|
        within("article[data-book-id='#{selected_book.id}']") do
          click_button I18n.t("jjaek_books.choose")
          expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
        end
      end
    end
    within("#book-selection-window") do
      expect(page).to have_text(book.title)
      click_button I18n.t("jjaek_books.finish_selection")
    end
    expect(page).to have_current_path(root_path)
    expect(page).to have_css("#jjaek-publish-form textarea[name='jjaek[content]']:focus")
    within("#jjaek-attached-books") do
      [ book, other_book ].each do |selected_book|
        within("[data-book-key='#{selected_book.id}']") do
          expect(page).to have_text(selected_book.title)
          expect(page).to have_css("img[src='#{selected_book.thumbnail}']")
          expect(page).to have_button(I18n.t("jjaek_books.remove_book", title: selected_book.title), enable_aria_label: true)
          expect(page).to have_button(I18n.t("jjaek_books.add_to_shelf"))
        end
      end
    end
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq([ "", book.id.to_s, other_book.id.to_s ])
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    third_book = Book.create!(title: "Search attachment third")
    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      fill_in "book-selection-query", with: third_book.title
      click_button I18n.t("book_search.form.submit")
    end
    within("#book-selection-search-results article[data-book-id='#{third_book.id}']") do
      click_button I18n.t("jjaek_books.choose")
      expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
    end
    within("#book-selection-window") do
      click_button I18n.t("jjaek_books.remove_book", title: book.title), enable_aria_label: true
      expect(page).to have_no_css("[data-book-selection-target='book'][data-book-id='#{book.id}']")
    end
    page.execute_script("Turbo.visit(arguments[0])", book_path(other_book))
    expect(page).to have_current_path(book_path(other_book))
    expect(page).to have_no_css("#book-jjaek-form")
    within("#book-selection-window") do
      expect(page).to have_css("[data-book-selection-target='book'][data-book-id='#{third_book.id}']")
      click_button I18n.t("book_search.actions.close")
    end
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_css("#book-selection-window")
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq([ "", book.id.to_s, other_book.id.to_s ])
    within("#jjaek-attached-books [data-book-key='#{book.id}']") { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("dialog[open]") { click_button I18n.t("bookshelves.actions.close") }
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    within("#jjaek-attached-books [data-book-key='#{book.id}']") { click_button I18n.t("jjaek_books.add_to_shelf") }
    within("dialog[open]") do
      choose shelf.name, allow_label_click: true
      click_button I18n.t("book_search.actions.add_to_shelf")
    end
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_field("jjaek[content]", with: "My draft survives")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(shelf)
    within("#jjaek-attached-books [data-book-key='#{book.id}']") do
      click_button I18n.t("jjaek_books.remove_book", title: book.title), enable_aria_label: true
    end
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key='#{book.id}']")
    expect(page).to have_css("#jjaek-attached-books [data-book-key='#{other_book.id}']")
    expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq([ "", other_book.id.to_s ])
    expect(user.jjaeks.where(content: "My draft survives")).to be_empty
    click_button I18n.t("jjaeks.actions.publish_short")
    expect(page).to have_text("My draft survives")
    saved = user.jjaeks.find_by!(content: "My draft survives")
    expect(saved.attached_books).to eq([ other_book ])
    expect(saved).to be_private_jjaek
    within("#jjaek_#{saved.id}") do
      expect(page).to have_text(other_book.title)
      expect(page).to have_css("img[src='#{other_book.thumbnail}']")
      expect(page).to have_link(other_book.title)
      expect(page).to have_no_text(book.title)
    end
    expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(shelf)
  end

  it "focuses the mobile body when completing an empty selection without leaving the page" do
    page.current_window.resize_to(390, 844)
    visit root_path
    fill_in "jjaek[content]", with: "Continue writing here"
    choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true
    click_button I18n.t("jjaek_books.add")
    within("#book-selection-window") do
      click_button I18n.t("jjaek_books.finish_selection")
    end

    expect(page).to have_current_path(root_path)
    expect(page).to have_no_css("#book-selection-window")
    expect(page).to have_css("#jjaek-publish-form textarea[name='jjaek[content]']:focus")
    expect(page).to have_field("jjaek[content]", with: "Continue writing here")
    expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all)
    expect(page).to have_no_css("#jjaek-attached-books [data-book-key]")
    expect(user.jjaeks.where(content: "Continue writing here")).to be_empty
  end

  it "cancels to the opening attachments through Close, search Back and browser Back without changing the draft context" do
    club = Group.create!(name: "Draft club", group_admin: user, lifecycle_status: :active)
    recipient = User.create!(name: "Draft recipient", email: "draft-recipient@example.com", password: "password123!")
    BookFriendship.create!(requester: user, addressee: recipient, status: :accepted)
    [ [ root_path, [], :close, nil, nil ], [ book_path(book), [ book.id ], :back, nil, nil ],
     [ group_path(club), [], :browser_back, club.id, nil ], [ user_path(recipient), [], :close, nil, recipient.id ] ].each do |origin, original_ids, exit_method, group_id, target_id|
      visit origin
      fill_in "jjaek[content]", with: "Cancel keeps this draft"
      choose I18n.t("jjaeks.visibility.private_jjaek"), allow_label_click: true unless group_id || target_id
      click_button I18n.t("jjaek_books.add")
      within("#book-selection-window") do
        fill_in "book-selection-query", with: "Search attachment"
        click_button I18n.t("book_search.form.submit")
      end
      within("#book-selection-search-results") do
        [ book, other_book ].reject { |item| original_ids.include?(item.id) }.each do |item|
          within("article[data-book-id='#{item.id}']") do
            click_button I18n.t("jjaek_books.choose")
            expect(page).to have_button(I18n.t("jjaek_books.selected"), disabled: true)
          end
        end
      end
      case exit_method
      when :close
        within("#book-selection-window") { click_button I18n.t("book_search.actions.close") }
      when :back
        find("main a[data-back-link]").click
      when :browser_back
        page.go_back
      end
      expect(page).to have_current_path(origin)
      expect(page).to have_no_css("#book-selection-window")
      expect(page).to have_field("jjaek[content]", with: "Cancel keeps this draft")
      expect(page).to have_no_css("#jjaek-publish-form textarea[name='jjaek[content]']:focus")
      expect(page).to have_checked_field(I18n.t("jjaeks.visibility.private_jjaek"), visible: :all) unless group_id || target_id
      expect(page.find("#jjaek-composer")["data-group-id"]).to eq(group_id.to_s)
      expect(page.find("#jjaek-composer")["data-target-user-id"]).to eq(target_id.to_s)
      expect(page.evaluate_script("new FormData(document.getElementById('jjaek-publish-form')).getAll('selected_books[]')")).to eq([ "", *original_ids.map(&:to_s) ])
    end
    expect(user.jjaeks.where(content: "Cancel keeps this draft")).to be_empty
    expect(user.bookshelf_entries).to be_empty
  end

  it "edits a legacy recommendation on the same Rails form and cancels navigation without saving" do
    visit edit_jjaek_path(recommendation)
    expect(page).to have_field("jjaek[content]", with: "Original recommendation")
    expect(page).to have_text(book.title)
    fill_in "jjaek[content]", with: "Discarded draft"
    visit root_path
    expect(recommendation.reload.content).to eq("Original recommendation")
    visit edit_jjaek_path(recommendation)
    within("#jjaek-attached-books") { click_button I18n.t("jjaek_books.remove_book", title: book.title), enable_aria_label: true }
    fill_in "jjaek[content]", with: "Edited without books"
    click_button I18n.t("jjaeks.actions.save")
    expect(page).to have_text("Edited without books")
    expect(recommendation.reload.attached_books).to be_empty
    expect(recommendation.content).to eq("Edited without books")
  end
end
