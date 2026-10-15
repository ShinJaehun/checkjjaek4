require "rails_helper"

RSpec.describe "Current reading information on book jjaeks", type: :request do
  let(:author) { User.create!(name: "Author", email: "reading-author@example.com", password: "password123!") }
  let(:viewer) { User.create!(name: "Viewer", email: "reading-viewer@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Reading context", authors_text: "Book author") }
  let(:shelf) { author.bookshelves.create!(name: "Reading shelf", visibility: :public) }
  let!(:entry) { author.bookshelf_entries.create!(book: book, bookshelf: shelf, status: :reading) }
  let!(:sticker) { StickerDefinition.create!(key: "current_reading_test", name: "CURRENT_READING_STICKER") }
  let!(:jjaek) { author.jjaeks.create!(book: book, content: "Book thoughts") }

  before { entry.sticker_definitions << sticker }

  def reading_info
    Nokogiri::HTML(response.body).css("[data-current-reading-state]").text
  end

  def befriend
    BookFriendship.create!(requester: viewer, addressee: author, status: :accepted)
  end

  it "shows the current state and stickers to the author, including on private shelves" do
    shelf = author.bookshelves.create!(name: "Private", visibility: :private)
    entry.update!(bookshelf: shelf)
    sign_in author
    get jjaek_path(jjaek)

    expect(response).to have_http_status(:ok)
    expect(reading_info).to include(I18n.t("bookshelf_entries.statuses.reading"), sticker.name)
    expect(reading_info).not_to include("현재 독서 정보")
    badges = Nokogiri::HTML(response.body).at_css("[data-current-reading-state]")
    expect(badges.at_css("[data-reading-status] svg")).to be_present
    expect(badges.at_css("[data-reading-sticker] svg")).to be_present
  end

  it "keeps the requote author's reading badges without a title label" do
    viewer_entry = viewer.bookshelf_entries.create!(book: book, status: :wish)
    viewer_entry.sticker_definitions << sticker
    requote = viewer.jjaeks.create!(book: book, quoted_jjaek: jjaek, content: "Requote thoughts")
    sign_in viewer

    get jjaek_path(requote)

    expect(response).to have_http_status(:ok)
    expect(reading_info).to include(I18n.t("bookshelf_entries.statuses.wish"), sticker.name)
    expect(reading_info).not_to include("현재 독서 정보")
  end

  it "rechecks current state, shelf visibility, and removal for an accepted friend" do
    befriend
    sign_in viewer
    get jjaek_path(jjaek)
    expect(reading_info).to include(sticker.name)

    entry.update!(status: :finished)
    entry.sticker_definitions.clear
    get jjaek_path(jjaek)
    expect(reading_info).to include(I18n.t("bookshelf_entries.statuses.finished"))
    expect(reading_info).not_to include(sticker.name)

    entry.bookshelf.update!(visibility: :private)
    get jjaek_path(jjaek)
    expect(reading_info).to be_empty

    entry.destroy!
    get jjaek_path(jjaek)
    expect(response).to have_http_status(:ok)
    expect(reading_info).to be_empty
  end

  it "uses the author's entry rather than the viewer's and omits empty information" do
    viewer.bookshelf_entries.create!(book: book, status: :wish)
    befriend
    sign_in viewer
    get jjaek_path(jjaek)
    expect(reading_info).to include(I18n.t("bookshelf_entries.statuses.reading"))
    expect(reading_info).not_to include(I18n.t("bookshelf_entries.statuses.wish"))

    entry.update!(status: nil)
    entry.sticker_definitions.clear
    get jjaek_path(jjaek)
    expect(reading_info).to be_empty
  end

  it "does not show public shelf metadata to a stranger or follow-only viewer" do
    sign_in viewer
    get jjaek_path(jjaek)
    expect(reading_info).to be_empty
    expect(response.body).not_to include(sticker.name)

    viewer.active_follows.create!(followee: author)
    get jjaek_path(jjaek)
    expect(reading_info).to be_empty
    expect(response.body).not_to include(sticker.name)
  end

  it "keeps personal shelf access independent of group membership" do
    group = Group.create!(name: "Reading group", group_admin: author, group_type: :public_group, lifecycle_status: :active)
    group_post = author.jjaeks.create!(book: book, group: group, content: "Group thoughts")
    sign_in viewer
    get jjaek_path(group_post)
    expect(response).to have_http_status(:ok)
    expect(reading_info).to be_empty

    befriend
    get jjaek_path(group_post)
    expect(reading_info).to include(sticker.name)

    entry.bookshelf.update!(visibility: :private)
    get group_path(group)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(sticker.name)
  end

  it "loads reading entries and stickers in a fixed number of queries for a book list" do
    befriend
    sign_in viewer
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM "(?:bookshelf_entries|sticker_definitions|bookshelf_entry_stickers)"/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get book_path(book) }
    single_card_query_count = queries.size
    expect(single_card_query_count).to be_positive
    3.times { |index| author.jjaeks.create!(book: book, content: "More thoughts #{index}") }
    queries.clear
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get book_path(book) }

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("[data-current-reading-state]").size).to eq(4)
    expect(queries.size).to eq(single_card_query_count)
  end
end
