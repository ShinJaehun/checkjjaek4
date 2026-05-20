require "rails_helper"

RSpec.describe "User libraries", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "reader-library@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Target Book", authors_text: "Target Author") }
  let!(:selected_bookshelf) { user.bookshelves.create!(name: "Selected Shelf", visibility: :private) }
  let!(:target_bookshelf) { user.bookshelves.create!(name: "Target Shelf", visibility: :private) }

  before do
    user.bookshelf_entries.create!(book:, bookshelf: target_bookshelf)
  end

  it "renders source and target lists on the transfer screen" do
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
    expect(document.at_css(%([data-bookshelf-transfer-bookshelf-id="#{target_bookshelf.id}"] article[data-bookshelf-entry-id="#{entry.id}"][data-bookshelf-entry-view="compact"]))).to be_present
  end

  it "does not render transfer drag targets on the default library screen" do
    sign_in user

    get user_library_path(user, bookshelf_id: selected_bookshelf.id, sort: "manual")

    document = Nokogiri::HTML(response.body)

    expect(document.at_css(%([data-controller="bookshelf-transfer"]))).to be_nil
    expect(document.at_css(%([data-bookshelf-transfer-target="list"]))).to be_nil
  end

  it "redirects transfer mode to the library when the user has one bookshelf" do
    lone_user = User.create!(name: "One Shelf", email: "one-shelf@example.com", password: "password123!", password_confirmation: "password123!")
    sign_in lone_user

    get transfer_user_library_path(lone_user)

    expect(response).to redirect_to(user_library_path(lone_user))
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

    get transfer_user_library_path(user)

    expect(response).to redirect_to(user_library_path(user))
  end
end
