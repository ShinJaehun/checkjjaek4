require "rails_helper"
require "digest/md5"

RSpec.describe "Discoveries", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:viewer) { User.create!(name: "Viewer", email: "discovery-viewer@example.com", password: "password123!") }
  let(:writer) { User.create!(name: "Writer", email: "discovery-writer@example.com", password: "password123!") }

  def get_published_discovery
    tomorrow_in_seoul = Time.current.in_time_zone("Asia/Seoul").tomorrow.beginning_of_day + 12.hours
    travel_to(tomorrow_in_seoul) { get discovery_path }
  end

  it "requires sign in" do
    get discovery_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows all four empty sections when there are no candidates" do
    sign_in viewer
    get_published_discovery

    expect(response).to have_http_status(:ok)
    %w[book_jjaeks general_jjaeks library group].each do |section|
      expect(response.body).to include(I18n.t("discovery.#{section}.empty"))
    end
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#discovery_book_jjaeks h2").text).to eq(I18n.t("discovery.book_jjaeks.title"))
    publication_date = Time.current.in_time_zone("Asia/Seoul").tomorrow.to_date
    expect(page.at_css("#discovery_header p").text).to eq(I18n.l(publication_date, format: :discovery))
    expect(page.css("a[href*='refresh']")).to be_empty
  end

  it "keeps all recommendation choices and post order stable for a Seoul publication date" do
    seoul = Time.find_zone!("Asia/Seoul")
    authors = []
    books = []
    groups = []
    posts = []
    travel_to(seoul.local(2026, 10, 29, 12)) do
      4.times do |index|
        author = User.create!(name: "Reader #{index}", email: "discovery-reader-#{index}@example.com", password: "password123!")
        book = Book.create!(title: "Daily book #{index}")
        authors << author
        books << book
        posts << author.jjaeks.create!(content: "Daily post #{index}", visibility: :public_jjaek)
        author.jjaeks.create!(book:, content: "Daily book post #{index}", visibility: :public_jjaek)
        author.bookshelf_entries.create!(book:)
        groups << Group.create!(group_admin: author, name: "Daily club #{index}", group_type: :public_group,
                                lifecycle_status: :active)
      end
    end
    sign_in viewer

    [ Date.new(2026, 10, 30), Date.new(2026, 10, 31) ].each do |date|
      expected_book = books.min_by { |book| [ Digest::MD5.hexdigest("#{date}:#{book.id}"), book.id ] }
      expected_library = authors.min_by { |author| [ Digest::MD5.hexdigest("#{date}:#{author.id}"), author.id ] }
      expected_group = groups.min_by { |group| [ Digest::MD5.hexdigest("#{date}:#{group.id}"), group.id ] }
      expected_posts = authors.sort_by { |author| [ Digest::MD5.hexdigest("#{date}:#{author.id}"), author.id ] }
        .first(3).map { |author| posts.find { |post| post.user_id == author.id }.id }

      [ 9, 23 ].each do |hour|
        travel_to(seoul.local(date.year, date.month, date.day, hour)) { get discovery_path }
        page = Nokogiri::HTML(response.body)

        expect(page.at_css("#discovery_book_jjaeks h3 a")["href"]).to eq(book_path(expected_book, return_to: discovery_path))
        expect(page.css("#discovery_general_jjaeks article a[href^='/jjaeks/']").map { |link| link["href"].split("/")[2].to_i }).to eq(expected_posts)
        expect(page.at_css("#discovery_library a[href^='/users/']")["href"]).to eq(user_path(expected_library))
        expect(page.at_css("#discovery_group h3 a")["href"]).to eq(group_path(expected_group))
        expect(page.at_css("#discovery_header p").text).to eq(I18n.l(date, format: :discovery))
        expect(page.at_css("#discovery_header p").text).to eq("2026년 10월 31일 토요일") if date == Date.new(2026, 10, 31)
      end
    end
  end

  it "includes posts only after the next Seoul midnight" do
    seoul = Time.find_zone!("Asia/Seoul")
    book = Book.create!(title: "MIDNIGHT_BOOK")
    group = Group.create!(group_admin: writer, name: "MIDNIGHT_GROUP", group_type: :public_group, lifecycle_status: :active)
    travel_to(seoul.local(2026, 10, 30, 12)) do
      writer.jjaeks.create!(book:, content: "OLD_BOOK_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(content: "OLD_GENERAL_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(group:, content: "OLD_GROUP_POST")
    end
    sign_in viewer

    travel_to(seoul.local(2026, 10, 31, 23, 59, 59)) do
      writer.jjaeks.create!(book:, content: "NEW_BOOK_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(content: "NEW_GENERAL_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(group:, content: "NEW_GROUP_POST")
      get discovery_path
      expect(response.body).to include("OLD_BOOK_POST", "OLD_GENERAL_POST", "OLD_GROUP_POST")
      expect(response.body).not_to include("NEW_BOOK_POST", "NEW_GENERAL_POST", "NEW_GROUP_POST")
    end

    travel_to(seoul.local(2026, 11, 1, 0, 0, 0)) { get discovery_path }
    expect(response.body).to include("NEW_BOOK_POST", "NEW_GENERAL_POST", "NEW_GROUP_POST")
  end

  it "reapplies hidden, visibility, and club access rules within the same day" do
    seoul = Time.find_zone!("Asia/Seoul")
    group = Group.create!(group_admin: writer, name: "ACCESS_GROUP", group_type: :public_group, lifecycle_status: :active)
    post = nil
    travel_to(seoul.local(2026, 10, 30, 12)) do
      post = writer.jjaeks.create!(content: "ACCESS_GENERAL_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(group:, content: "ACCESS_GROUP_POST")
    end
    sign_in viewer

    travel_to(seoul.local(2026, 10, 31, 12)) do
      get discovery_path
      expect(response.body).to include("ACCESS_GENERAL_POST", "ACCESS_GROUP_POST")

      post.update_columns(hidden_at: Time.current)
      group.update_columns(group_type: Group.group_types.fetch("approval_group"))
      get discovery_path
      expect(response.body).not_to include("ACCESS_GENERAL_POST", "ACCESS_GROUP_POST")
      expect(response.body).to include(I18n.t("discovery.group.approval_required"))

      post.update_columns(hidden_at: nil, visibility: Jjaek.visibilities.fetch("private_jjaek"))
      get discovery_path
      expect(response.body).not_to include("ACCESS_GENERAL_POST")
    end
  end

  it "shows public original book and general posts with existing detail links" do
    book = Book.create!(title: "A public book", authors_text: "A writer")
    book_post = writer.jjaeks.create!(book:, content: "PUBLIC_BOOK_POST", visibility: :public_jjaek)
    general_post = writer.jjaeks.create!(content: "PUBLIC_GENERAL_POST", visibility: :public_jjaek)
    sign_in viewer
    get_published_discovery

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
    get_published_discovery

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
    get_published_discovery

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
    get_published_discovery

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
    get_published_discovery

    expect(response.body).to include("LATEST_GROUP_POST", "SECOND_GROUP_POST", "THIRD_GROUP_POST",
                                    "GROUP_POST_BOOK", jjaek_path(latest), jjaek_path(second), jjaek_path(third))
    expect(response.body).not_to include("FOURTH_GROUP_POST", jjaek_path(fourth))
    page = Nokogiri::HTML(response.body)
    cover_link = page.css(%Q(#discovery_group a[href="#{book_path(book, return_to: discovery_path)}"])).find { |link| link.at_css("div") }
    expect(cover_link).to be_present
    expect(cover_link.at_css("div")["class"]).to include("h-12", "md:h-16")
  end

  it "shows a recent post to an active approval group member" do
    group = Group.create!(group_admin: writer, name: "MEMBER_ACTIVITY_GROUP", group_type: :approval_group,
                          lifecycle_status: :active)
    group.group_memberships.create!(user: viewer, status: :active)
    post = writer.jjaeks.create!(group:, content: "MEMBER_VISIBLE_POST")
    sign_in viewer
    get_published_discovery

    expect(response.body).to include("MEMBER_VISIBLE_POST", jjaek_path(post))
    expect(response.body).not_to include(I18n.t("discovery.group.approval_required"))
    expect(Nokogiri::HTML(response.body).css("#discovery_group a[href^='/books/']")).to be_empty
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
    get_published_discovery

    expect(response.body).to include("VISIBLE_GROUP_POST", jjaek_path(visible))
    expect(response.body).not_to include("HIDDEN_GROUP_POST", "DELETED_GROUP_POST", "INACCESSIBLE_QUOTE_POST")
  end

  it "prefers a group the viewer has not joined" do
    joined = Group.create!(group_admin: viewer, name: "ALREADY_MEMBER_GROUP", group_type: :public_group, lifecycle_status: :active)
    unjoined = Group.create!(group_admin: writer, name: "UNJOINED_GROUP", group_type: :public_group, lifecycle_status: :active)
    sign_in viewer
    get_published_discovery

    expect(response.body).to include(group_path(unjoined), "UNJOINED_GROUP")
    expect(response.body).not_to include(group_path(joined), "ALREADY_MEMBER_GROUP")
  end
end
