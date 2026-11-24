require "rails_helper"

RSpec.describe "User libraries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Target Book", authors_text: "Target Author") }
  let!(:selected_bookshelf) { user.bookshelves.create!(name: "Selected Shelf", visibility: :private) }
  let!(:target_bookshelf) { user.bookshelves.create!(name: "Target Shelf", visibility: :private) }

  before do
    user.bookshelf_entries.create!(book:, bookshelf: target_bookshelf)
  end

  it "uses shared badges for reading information in the library" do
    entry = user.bookshelf_entries.find_by!(book: book)
    entry.user_book.update!(status: :reading)
    sticker = StickerDefinition.create!(key: "recommended_to_me", name: "Legacy recommendation label")
    entry.user_book.sticker_definitions << sticker
    sign_in user

    get user_library_path(user, bookshelf_id: target_bookshelf.id)

    card = Nokogiri::HTML(response.body).at_css("[data-bookshelf-entry-id='#{entry.id}']")
    expect(card.at_css('[data-reading-status="reading"] svg')).to be_present
    expect(card.at_css('[data-reading-sticker="recommended_to_me"] svg')).to be_present
    icon = card.at_css('[data-reading-sticker="recommended_to_me"]')
    expect(icon.text).to be_empty
    expect(icon["title"]).to eq(I18n.t("reading_experience.stickers.recommended_to_me"))
    expect(icon["aria-label"]).to eq(icon["title"])
    expect(card.text).to include(I18n.t("bookshelf_entries.statuses.reading"))
    expect(card.text).not_to include(sticker.name)
  end

  it "prepares all six ordered sticker icons and an accessible initial summary in the information dialogs" do
    entry = user.bookshelf_entries.find_by!(book: book)
    stickers = %w[loved_it really_loved_it stayed_with_me want_to_reread recommended_to_me want_to_recommend].map do |key|
      StickerDefinition.create!(key: key, name: key)
    end
    entry.user_book.sticker_definitions << stickers
    sign_in user

    paths = [
      user_library_path(user, bookshelf_id: target_bookshelf.id),
      transfer_user_library_path(user, source_bookshelf_id: target_bookshelf.id, target_bookshelf_id: selected_bookshelf.id)
    ]
    paths.each do |path|
      get path
      expect(response).to have_http_status(:ok)
      card = Nokogiri::HTML(response.body).at_css("[data-bookshelf-entry-id='#{entry.id}'] dialog")
      icons = card.css("[data-reading-sticker]")
      expect(icons.map { |icon| icon["data-reading-sticker"] }).to eq(stickers.map(&:key))
      expect(icons.all? { |icon| icon.at_css("svg") && icon.text.empty? && icon["title"] == icon["aria-label"] }).to be(true)
      overflow = card.at_css("[data-reading-sticker-overflow]")
      expect(overflow.text).to eq("+3")
      names = stickers.drop(3).map { |sticker| I18n.t("reading_experience.stickers.#{sticker.key}") }.join(", ")
      expect(overflow["title"]).to eq(names)
      expect(overflow["aria-label"]).to include(names)
      expect(card.css("[data-reading-status-row], [data-reading-stickers-row]").size).to eq(2)
      expect(card.at_css("[data-reading-stickers-row]")["data-controller"]).to eq("sticker-overflow")
    end
  end

  it "keeps the library header and links both bookshelf tasks to the selected shelf" do
    sign_in user

    get user_library_path(user)

    document = Nokogiri::HTML(response.body)
    header = document.at_css("header[data-library-summary]")
    expect(header["class"].split).to include("bg-white", "rounded-2xl", "border", "border-stone-200", "shadow-sm", "p-4")
    expect(header.at_css("img")["class"].split).to include("h-12", "w-12", "shrink-0")
    expect(header.at_css("[data-library-bookshelf-summary]")).to be_nil
    source_id = user.default_bookshelf.id
    actions = document.at_css("#library-bookshelves").element_children.first
    expect(actions.css("button, a").map { |control| control.text.squish }).to eq([
      I18n.t("book_search.nav"), I18n.t("bookshelves.actions.new"),
      I18n.t("users.library.transfer.title"), I18n.t("users.library.transfer.organize")
    ])
    expect(actions.css("a").map { |link| link["href"] }).to eq([
      transfer_user_library_path(user, source_bookshelf_id: source_id),
      transfer_user_library_path(user, mode: "organize", source_bookshelf_id: source_id)
    ])
    expect(header.at_css("h1").text).to eq("Reader의 서재")
    expect(header.css("li, [data-bookshelf-visibility]")).to be_empty
    expect(document.at_css('[data-bookshelf-visibility="public"]')).to be_present
    tabs = document.at_css("[data-library-tabs]")
    expect(tabs.at_css('[aria-current="page"]').text).to eq(I18n.t("users.library.tabs.bookshelves"))
    expect(document.at_css("#library-bookshelves button[aria-controls='global-book-search-dialog']").text.strip).to eq(I18n.t("book_search.nav"))
    expect(document.at_css("#book-notes")).to be_nil

    get tabs.at_css("[data-library-notes-link]")["href"]
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[data-library-notes-link][aria-current="page"]')).to be_present
    expect(document.at_css("#library-bookshelves")).to be_nil
    expect(document.at_css("#book-notes").text).to include(I18n.t("book_notes.empty"))
  end

  it "lists only public and book-friends shelves in another user's library" do
    friend = User.create!(name: "Friend", email: "summary-friend@example.com", password: "password123!")
    BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
    public_shelf = user.bookshelves.create!(name: "Public Summary", visibility: :public)
    friend_shelf = user.bookshelves.create!(name: "Friends Summary", visibility: :book_friends)
    friend_entry = user.bookshelf_entries.create!(book: Book.create!(title: "Friend summary book"), bookshelf: friend_shelf)
    sign_in friend

    get user_library_path(user)

    options = Nokogiri::HTML(response.body).css("select[data-library-mobile-bookshelf-select] option")
    expect(options.map { |option| option["value"] }).to match_array([ user.default_bookshelf.id, public_shelf.id, friend_shelf.id ].map(&:to_s))
    expect(options.find { |option| option["value"] == friend_shelf.id.to_s }.text).to eq("#{friend_shelf.name} (1)")
    expect(response.body).not_to include("Target Shelf", "Selected Shelf")

    get user_library_path(user, bookshelf_id: friend_shelf.id)

    card = Nokogiri::HTML(response.body).at_css(%(article[data-bookshelf-entry-id="#{friend_entry.id}"] dialog))
    expect(card).to be_present
    expect(card.at_css(%(form[action="#{bookshelf_entry_path(friend_entry)}"]))).to be_nil
  end

  it "does not list private shelves for an admin book friend" do
    admin_friend = User.create!(name: "Admin Friend", email: "summary-admin-friend@example.com", password: "password123!", global_admin: true)
    BookFriendship.create!(requester: user, addressee: admin_friend, status: :accepted)
    sign_in admin_friend

    get user_library_path(user)

    expect(response).to have_http_status(:ok)
    options = Nokogiri::HTML(response.body).css("select[data-library-mobile-bookshelf-select] option")
    expect(options.map { |option| option["value"] }).to eq([ user.default_bookshelf.id.to_s ])
    expect(response.body).not_to include(selected_bookshelf.name, target_bookshelf.name)
  end

  it "redirects a global admin without book friendship away from another user's library" do
    admin = User.create!(
      name: "Admin",
      email: "library-global-admin@example.com",
      password: "password123!",
      global_admin: true
    )
    sign_in admin

    get user_library_path(user, bookshelf_id: target_bookshelf.id)

    expect(response).to redirect_to(user_path(user))
  end

  it "renders source and target lists on the transfer screen" do
    source_book = Book.create!(title: "Source Book", authors_text: "Source Author")
    source_entry = user.bookshelf_entries.create!(book: source_book, bookshelf: selected_bookshelf)
    sign_in user

    get transfer_user_library_path(user, source_bookshelf_id: selected_bookshelf.id, target_bookshelf_id: target_bookshelf.id)

    document = Nokogiri::HTML(response.body)
    entry = user.bookshelf_entries.find_by!(book:)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target Shelf")
    expect(response.body).to include(I18n.t("users.library.transfer.source_label"))
    expect(response.body).to include(I18n.t("users.library.transfer.target_label"))
    expect(response.body).not_to include("spike")
    expect(document.css(%([data-bookshelf-transfer-target="list"])).size).to eq(2)
    expect(document.at_css(%([data-controller="bookshelf-transfer"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-target="selectionModeButton"]))).to be_nil
    expect(document.at_css(%([data-bookshelf-transfer-target="selectionBar"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-target="moveButton"][disabled]))).to be_present
    expect(document.at_css(%(select[data-bookshelf-transfer-source-select="true"][name="source_bookshelf_id"]))).to be_present
    expect(document.at_css(%(select[data-bookshelf-transfer-source-select="true"] option[value="#{selected_bookshelf.id}"]))&.text).to eq("Selected Shelf (1)")
    expect(document.at_css(%(select[data-bookshelf-transfer-source-select="true"] option[value="#{target_bookshelf.id}"]))&.text).to eq("Target Shelf (1)")
    expect(document.at_css(%(form[action="#{bulk_move_bookshelf_entries_path}"]))).to be_present
    expect(document.at_css(%(button[name="target_bookshelf_id"][value="#{target_bookshelf.id}"]))).to be_present
    expect(document.at_css(%(button[name="target_bookshelf_id"][value="#{selected_bookshelf.id}"]))).to be_nil
    expect(document.at_css(%(input[name="return_to_target_as_source"][value="1"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-target="selectionCheckboxWrapper"] input[type="checkbox"][value="#{source_entry.id}"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-target="list"][data-bookshelf-transfer-bookshelf-id="#{target_bookshelf.id}"] > article[data-bookshelf-entry-id="#{entry.id}"] button[data-bookshelf-cover]))).to be_present

    [ source_entry, entry ].each do |card_entry|
      card = document.at_css(%(article[data-bookshelf-entry-id="#{card_entry.id}"]))
      remove_form = card.at_css(%(dialog form[action="#{bookshelf_entry_path(card_entry)}"]))
      expect(remove_form.at_css("input[name='_method']")["value"]).to eq("delete")
      expect(remove_form.at_css("input[name='bookshelf_id']")["value"]).to eq(card_entry.bookshelf_id.to_s)
      expect(remove_form.at_css("input[name='source_bookshelf_id']")["value"]).to eq(selected_bookshelf.id.to_s)
      expect(remove_form.at_css("input[name='target_bookshelf_id']")["value"]).to eq(target_bookshelf.id.to_s)
    end
    expect(document.at_css(%(form[action="#{bulk_destroy_bookshelf_entries_path}"]))).to be_nil
  end

  it "organizes only the selected shelf and uses the existing bulk forms" do
    sign_in user

    get transfer_user_library_path(user, mode: "organize", source_bookshelf_id: target_bookshelf.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    lists = document.css(%([data-bookshelf-transfer-target="list"]))
    expect(lists.map { |list| list["data-bookshelf-transfer-bookshelf-id"] }).to eq([ target_bookshelf.id.to_s ])
    expect(document.at_css(%([data-bookshelf-entries-sort-handle]))).to be_nil
    expect(document.at_css(%([data-bookshelf-transfer-target="selectionModeButton"]))).to be_nil
    expect(document.at_css(%(a[href="#{transfer_user_library_path(user, mode: "organize", source_bookshelf_id: selected_bookshelf.id)}"]))).to be_present
    expect(document.at_css(%(form[action="#{bulk_move_bookshelf_entries_path}"] input[name="source_bookshelf_id"][value="#{target_bookshelf.id}"]))).to be_present
    bulk_remove_form = document.at_css(%(form[action="#{bulk_destroy_bookshelf_entries_path}"]))
    expect(bulk_remove_form.at_css("input[name='_method']")["value"]).to eq("delete")
    expect(document.at_css(%([role="dialog"] button[form="#{bulk_remove_form['id']}"])).text).to include(I18n.t("bookshelf_entries.actions.remove"))
  end

  it "does not render transfer drag targets on the default library screen" do
    sign_in user

    get user_library_path(user, bookshelf_id: target_bookshelf.id, sort: "manual")

    document = Nokogiri::HTML(response.body)
    entry = user.bookshelf_entries.find_by!(book:)

    expect(document.at_css(%(article[data-bookshelf-entry-id="#{entry.id}"]))).to be_present
    expect(document.at_css(%([data-controller="bookshelf-transfer"]))).to be_nil
    expect(document.at_css(%([data-bookshelf-transfer-target="selectionModeButton"]))).to be_nil
    expect(document.at_css(%(select[data-bookshelf-transfer-source-select="true"]))).to be_nil
    expect(document.at_css(%([data-bookshelf-transfer-target="list"]))).to be_nil
    expect(document.at_css(%(form[action="#{bulk_move_bookshelf_entries_path}"]))).to be_nil
    expect(document.at_css(%(dialog form[action="#{bookshelf_entry_path(entry)}"] input[name="bookshelf_id"][value="#{target_bookshelf.id}"]))).to be_present
    expect(document.at_css(%(form[action="#{bulk_destroy_bookshelf_entries_path}"]))).to be_nil
    expect(response.body).not_to include(I18n.t("users.library.transfer.selected_count_suffix"))
  end

  it "requires two shelves for moving and still allows organizing one shelf" do
    lone_user = User.create!(name: "One Shelf", email: "one-shelf@example.com", password: "password123!", password_confirmation: "password123!")
    sign_in lone_user

    get transfer_user_library_path(lone_user)

    expect(response).to redirect_to(user_library_path(lone_user))

    get transfer_user_library_path(lone_user, mode: "organize")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(%([data-bookshelf-transfer-target="list"])).size).to eq(1)
    expect(document.at_css(%(form[action="#{bulk_destroy_bookshelf_entries_path}"]))).to be_present
    expect(document.at_css(%(button[name="target_bookshelf_id"]))).to be_nil
  end

  it "adjusts the target bookshelf when source changed to the current target" do
    sign_in user

    get transfer_user_library_path(user, source_bookshelf_id: selected_bookshelf.id, target_bookshelf_id: selected_bookshelf.id, changed: "source")

    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(document.at_css(%([data-bookshelf-transfer-ui-source-bookshelf-id-value="#{selected_bookshelf.id}"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-ui-target-bookshelf-id-value="#{target_bookshelf.id}"]))).to be_present
  end

  it "adjusts the source bookshelf when target changed to the current source" do
    sign_in user

    get transfer_user_library_path(user, source_bookshelf_id: selected_bookshelf.id, target_bookshelf_id: selected_bookshelf.id, changed: "target")

    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(document.at_css(%([data-bookshelf-transfer-ui-source-bookshelf-id-value="#{target_bookshelf.id}"]))).to be_present
    expect(document.at_css(%([data-bookshelf-transfer-ui-target-bookshelf-id-value="#{selected_bookshelf.id}"]))).to be_present
  end

  it "redirects book friends away from transfer mode" do
    friend = User.create!(name: "Friend", email: "transfer-friend@example.com", password: "password123!", password_confirmation: "password123!")
    BookFriendship.create!(requester: friend, addressee: user, status: :accepted)
    sign_in friend

    [ nil, "organize" ].each do |mode|
      get transfer_user_library_path(user, mode:)

      expect(response).to redirect_to(user_library_path(user))
    end
  end
end
