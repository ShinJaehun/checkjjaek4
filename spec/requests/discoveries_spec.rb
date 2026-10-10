require "rails_helper"

RSpec.describe "Discoveries", type: :request do
  let(:viewer) { User.create!(name: "Viewer", email: "discovery-viewer@example.com", password: "password123!") }
  let(:writer) { User.create!(name: "Writer", email: "discovery-writer@example.com", password: "password123!") }

  it "requires sign in" do
    get discovery_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows all four empty sections when there are no candidates" do
    sign_in viewer
    get discovery_path

    expect(response).to have_http_status(:ok)
    %w[book_jjaeks general_jjaeks library group].each do |section|
      expect(response.body).to include(I18n.t("discovery.#{section}.empty"))
    end
  end

  it "shows public original book and general posts with existing detail links" do
    book = Book.create!(title: "A public book", authors_text: "A writer")
    book_post = writer.jjaeks.create!(book:, content: "PUBLIC_BOOK_POST", visibility: :public_jjaek)
    general_post = writer.jjaeks.create!(content: "PUBLIC_GENERAL_POST", visibility: :public_jjaek)
    sign_in viewer
    get discovery_path

    expect(response.body).to include("A public book", "A writer", "PUBLIC_BOOK_POST", "PUBLIC_GENERAL_POST")
    expect(response.body).to include(book_path(book), jjaek_path(book_post), jjaek_path(general_post))
  end

  it "excludes restricted, hidden, deleted, requoted, group, and own general posts" do
    original = writer.jjaeks.create!(content: "PUBLIC_ORIGINAL", visibility: :public_jjaek)
    writer.jjaeks.create!(content: "FRIENDS_POST", visibility: :book_friends)
    writer.jjaeks.create!(content: "PRIVATE_POST", visibility: :private_jjaek)
    hidden = writer.jjaeks.create!(content: "HIDDEN_POST", visibility: :public_jjaek)
    hidden.update_columns(hidden_at: Time.current)
    deleted = writer.jjaeks.create!(content: "DELETED_POST", visibility: :public_jjaek)
    deleted.update_columns(deleted_at: Time.current)
    writer.jjaeks.create!(content: "REQUOTED_POST", quoted_jjaek: original, visibility: :public_jjaek)
    viewer.jjaeks.create!(content: "OWN_GENERAL_POST", visibility: :public_jjaek)
    group = Group.create!(group_admin: writer, name: "An approval group", group_type: :approval_group, lifecycle_status: :active)
    writer.jjaeks.create!(group:, content: "GROUP_POST", visibility: :public_jjaek)
    sign_in viewer
    get discovery_path

    expect(response.body).to include("PUBLIC_ORIGINAL")
    expect(response.body).not_to include("FRIENDS_POST", "PRIVATE_POST", "HIDDEN_POST", "DELETED_POST",
                                        "REQUOTED_POST", "OWN_GENERAL_POST", "GROUP_POST")
  end

  it "counts and shows only public bookshelf books in the recommended library" do
    public_book = Book.create!(title: "VISIBLE_LIBRARY_BOOK")
    friend_book = Book.create!(title: "FRIEND_LIBRARY_BOOK")
    private_book = Book.create!(title: "PRIVATE_LIBRARY_BOOK")
    writer.bookshelf_entries.create!(book: public_book)
    friend_shelf = writer.bookshelves.create!(name: "Friends", visibility: :book_friends)
    private_shelf = writer.bookshelves.create!(name: "Private", visibility: :private)
    writer.bookshelf_entries.create!(book: friend_book, bookshelf: friend_shelf)
    writer.bookshelf_entries.create!(book: private_book, bookshelf: private_shelf)
    sign_in viewer
    get discovery_path

    expect(response.body).to include(user_path(writer), book_path(public_book), "공개 책 1권")
    expect(response.body).not_to include(book_path(friend_book), book_path(private_book))
  end

  it "recommends an active discoverable group without showing posts to an approval group nonmember" do
    group = Group.create!(group_admin: writer, name: "VISIBLE_GROUP", description: "Public introduction",
                          group_type: :approval_group, lifecycle_status: :active)
    writer.jjaeks.create!(group:, content: "INTERNAL_GROUP_POST")
    Group.create!(group_admin: writer, name: "PRIVATE_GROUP", group_type: :private_group, lifecycle_status: :active)
    Group.create!(group_admin: writer, name: "PENDING_GROUP", group_type: :public_group,
                  application_purpose: "Read together")
    Group.create!(group_admin: writer, name: "SUSPENDED_GROUP", group_type: :public_group,
                  lifecycle_status: :active, operation_suspended_at: Time.current)
    sign_in viewer
    get discovery_path

    expect(response.body).to include("VISIBLE_GROUP", "Public introduction", group_path(group))
    expect(response.body).to include(I18n.t("discovery.group.approval_required"))
    expect(response.body).not_to include("PRIVATE_GROUP", "PENDING_GROUP", "SUSPENDED_GROUP", "INTERNAL_GROUP_POST")
  end

  it "shows only the latest three readable posts from a public group" do
    group = Group.create!(group_admin: writer, name: "PUBLIC_ACTIVITY_GROUP", group_type: :public_group,
                          lifecycle_status: :active)
    fourth = writer.jjaeks.create!(group:, content: "FOURTH_GROUP_POST")
    third = writer.jjaeks.create!(group:, content: "THIRD_GROUP_POST")
    second = writer.jjaeks.create!(group:, content: "SECOND_GROUP_POST")
    book = Book.create!(title: "GROUP_POST_BOOK")
    latest = writer.jjaeks.create!(group:, book:, content: "LATEST_GROUP_POST")
    sign_in viewer
    get discovery_path

    expect(response.body).to include("LATEST_GROUP_POST", "SECOND_GROUP_POST", "THIRD_GROUP_POST",
                                    "GROUP_POST_BOOK", jjaek_path(latest), jjaek_path(second), jjaek_path(third))
    expect(response.body).not_to include("FOURTH_GROUP_POST", jjaek_path(fourth))
  end

  it "shows a recent post to an active approval group member" do
    group = Group.create!(group_admin: writer, name: "MEMBER_ACTIVITY_GROUP", group_type: :approval_group,
                          lifecycle_status: :active)
    group.group_memberships.create!(user: viewer, status: :active)
    post = writer.jjaeks.create!(group:, content: "MEMBER_VISIBLE_POST")
    sign_in viewer
    get discovery_path

    expect(response.body).to include("MEMBER_VISIBLE_POST", jjaek_path(post))
    expect(response.body).not_to include(I18n.t("discovery.group.approval_required"))
  end

  it "skips hidden, deleted, and inaccessible quoted group posts" do
    group = Group.create!(group_admin: writer, name: "FILTERED_ACTIVITY_GROUP", group_type: :public_group,
                          lifecycle_status: :active)
    visible = writer.jjaeks.create!(group:, content: "VISIBLE_GROUP_POST")
    hidden = writer.jjaeks.create!(group:, content: "HIDDEN_GROUP_POST")
    hidden.update_columns(hidden_at: Time.current)
    deleted = writer.jjaeks.create!(group:, content: "DELETED_GROUP_POST")
    deleted.update_columns(deleted_at: Time.current)
    source = writer.jjaeks.create!(content: "QUOTED_SOURCE", visibility: :public_jjaek)
    writer.jjaeks.create!(group:, quoted_jjaek: source, content: "INACCESSIBLE_QUOTE_POST")
    source.update_columns(visibility: Jjaek.visibilities.fetch("private_jjaek"))
    sign_in viewer
    get discovery_path

    expect(response.body).to include("VISIBLE_GROUP_POST", jjaek_path(visible))
    expect(response.body).not_to include("HIDDEN_GROUP_POST", "DELETED_GROUP_POST", "INACCESSIBLE_QUOTE_POST")
  end

  it "prefers a group the viewer has not joined" do
    joined = Group.create!(group_admin: viewer, name: "ALREADY_MEMBER_GROUP", group_type: :public_group, lifecycle_status: :active)
    unjoined = Group.create!(group_admin: writer, name: "UNJOINED_GROUP", group_type: :public_group, lifecycle_status: :active)
    sign_in viewer
    get discovery_path

    expect(response.body).to include(group_path(unjoined), "UNJOINED_GROUP")
    expect(response.body).not_to include(group_path(joined), "ALREADY_MEMBER_GROUP")
  end
end
