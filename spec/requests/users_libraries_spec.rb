require "rails_helper"

RSpec.describe "User libraries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book_friend) { User.create!(name: "Friend", email: "friend-organize-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Target Book", authors_text: "Target Author") }
  let!(:selected_bookshelf) { user.bookshelves.create!(name: "Selected Shelf", visibility: :private) }
  let!(:target_bookshelf) { user.bookshelves.create!(name: "Target Shelf", visibility: :private) }

  before do
    user.bookshelf_entries.create!(book:, bookshelf: target_bookshelf)
  end

  it "renders one cross-shelf sortable target for the owner in manual sort" do
    sign_in user

    get user_library_path(user, bookshelf_id: selected_bookshelf.id, target_bookshelf_id: target_bookshelf.id, view: "compact", sort: "manual")

    document = Nokogiri::HTML(response.body)
    entry = user.bookshelf_entries.find_by!(book:)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target Shelf")
    expect(response.body).to include(I18n.t("users.library.cross_shelf_target.label"))
    expect(response.body).not_to include("spike")
    expect(document.css(%([data-cross-shelf-sortable-target="list"])).size).to eq(2)
    expect(document.at_css(%([data-cross-shelf-sortable-bookshelf-id="#{target_bookshelf.id}"] article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="compact"]))).to be_present
    expect(document.at_css(%([data-bookshelf-dnd-before-entry-id-param]))).to be_nil
    expect(document.at_css(%([data-action*="dropOnInsertSlot"]))).to be_nil
  end

  it "does not render the cross-shelf target outside manual sort" do
    sign_in user

    get user_library_path(user, bookshelf_id: selected_bookshelf.id, sort: "title")

    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(document.at_css(%([data-controller="cross-shelf-sortable"]))).to be_nil
    expect(document.at_css(%([data-cross-shelf-sortable-target="list"]))).to be_nil
  end

  it "renders organize mode columns for the owner" do
    sign_in user

    get organize_user_library_path(user)

    document = Nokogiri::HTML(response.body)
    entry = user.bookshelf_entries.find_by!(book:)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("users.library.organize_title"))
    expect(response.body).to include("Selected Shelf")
    expect(response.body).to include("Target Shelf")
    expect(document.at_css(%([data-controller="bookshelf-organize"]))).to be_present
    expect(document.css(%([data-bookshelf-organize-target="column"])).size).to be >= 2
    expect(document.at_css(%([data-bookshelf-organize-bookshelf-id="#{target_bookshelf.id}"] article[data-bookshelf-entry-id="#{entry.id}"]))).to be_present
  end

  it "rejects organize mode for a non-owner" do
    BookFriendship.create!(requester: user, addressee: book_friend, status: :accepted)
    sign_in book_friend

    get organize_user_library_path(user)

    expect(response).to have_http_status(:forbidden)
  end
end
