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

  it "classifies unified and legacy attachments once and summarizes personal and group previews" do
    books = 5.times.map { |index| Book.create!(title: "Discovery attachment #{index}") }
    group = Group.create!(name: "Unified discovery group", group_admin: writer, group_type: :public_group, lifecycle_status: :active)
    sign_in writer
    post jjaeks_path, params: { selected_books: books.map(&:id), jjaek: { content: "Unified discovery books" } }
    unified = writer.jjaeks.find_by!(content: "Unified discovery books")
    expect(unified.attributes).not_to have_key("book_id")
    legacy = build_jjaek_with_books(legacy_source_kind: "recommendation", user: writer, content: "Legacy recommendation discovery")
    books.each_with_index { |book, position| legacy.jjaek_book_attachments.build(book: book, position: position) }
    legacy.save!
    post jjaeks_path, params: { selected_books: [ "" ], jjaek: { content: "No discovery books" } }
    post group_jjaeks_path(group), params: { selected_books: books.map(&:id), jjaek: { content: "Unified group discovery" } }
    sign_in viewer
    get_published_discovery

    page = Nokogiri::HTML(response.body)
    book_section = page.at_css("#discovery_book_jjaeks")
    expect(book_section.css("article").size).to eq(2)
    expect(book_section.text).to include(unified.content, legacy.content)
    general_section = page.at_css("#discovery_general_jjaeks")
    expect(general_section.text).to include("No discovery books")
    expect(general_section.text).not_to include(unified.content, legacy.content)
    previews = page.css("[data-discovery-attached-books]")
    expect(previews.size).to eq(3)
    previews.each do |preview|
      expect(preview.css("a").map(&:text)).to eq(books.first(3).map(&:title))
      expect(preview.text).to include(I18n.t("jjaek_books.additional_books", count: 2))
    end
    expect(response.body).to include("Unified group discovery")
  end

  it "excludes profile conversations from discovery even for a participant and with historical public visibility" do
    BookFriendship.create!(requester: writer, addressee: viewer, status: :accepted)
    book = Book.create!(title: "Conversation-only book")
    sign_in writer
    [ [], [ book.id ] ].each_with_index do |ids, index|
      post jjaeks_path, params: { selected_books: [ "", *ids ], jjaek: { target_user_id: viewer.id, content: "Conversation discovery #{index}" } }
      writer.jjaeks.find_by!(content: "Conversation discovery #{index}").update_column(:visibility, Jjaek.visibilities[:public_jjaek])
    end
    sign_in viewer
    get_published_discovery

    expect(response.body).not_to include("Conversation discovery", book.title)
    expect(Nokogiri::HTML(response.body).css("#discovery_book_jjaeks article, #discovery_general_jjaeks article")).to be_empty
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

  it "links tags in both discovery post previews to the global tag search" do
    book = Book.create!(title: "Tagged discovery book")
    writer.jjaeks.create!(content: "General #발견")
    create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, content: "Book #발견")
    sign_in viewer
    get_published_discovery

    page = Nokogiri::HTML(response.body)
    %w[general_jjaeks book_jjaeks].each do |section|
      link = page.css("#discovery_#{section} a").find { |anchor| anchor.text == "#발견" }
      expect(link["href"]).to eq(search_path(tag: "발견"))
    end
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
        create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: author, content: "Daily book post #{index}", visibility: :public_jjaek)
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
      create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, content: "OLD_BOOK_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(content: "OLD_GENERAL_POST", visibility: :public_jjaek)
      writer.jjaeks.create!(group:, content: "OLD_GROUP_POST")
    end
    sign_in viewer

    travel_to(seoul.local(2026, 10, 31, 23, 59, 59)) do
      create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, content: "NEW_BOOK_POST", visibility: :public_jjaek)
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
    book_post = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, content: "PUBLIC_BOOK_POST", visibility: :public_jjaek)
    general_post = writer.jjaeks.create!(content: "PUBLIC_GENERAL_POST", visibility: :public_jjaek)
    sign_in viewer
    get_published_discovery

    expect(response.body).to include("A public book", "A writer", "PUBLIC_BOOK_POST", "PUBLIC_GENERAL_POST")
    expect(response.body).to include(book_path(book), jjaek_path(book_post), jjaek_path(general_post))
    page = Nokogiri::HTML(response.body)
    { book_jjaeks: book_post, general_jjaeks: general_post }.each do |section, record|
      links = page.css("#discovery_#{section} article a")
      author_links = links.select { |link| link["href"] == user_path(writer) }
      expect(author_links.size).to eq(2) # Avatar and author name remain linked.
      expect(author_links.map(&:text).map(&:strip)).to include(writer.name)
      detail_links = links.select { |link| link["href"] == jjaek_path(record, return_to: discovery_path) }
      expect(detail_links.map(&:text)).to eq([ I18n.t("discovery.read_jjaek") ])
    end
    expect(page.css("#discovery_book_jjaeks article a").map { |link| link["href"] })
      .to include(book_path(book, return_to: discovery_path))
  end

  it "shows creation or latest edit consistently in book, general and group previews" do
    book = Book.create!(title: "Timestamp book")
    group = Group.create!(group_admin: writer, name: "Timestamp club", group_type: :public_group, lifecycle_status: :active)
    posts = {
      book_jjaeks: create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, content: "Book preview"),
      general_jjaeks: writer.jjaeks.create!(content: "General preview"),
      group: writer.jjaeks.create!(group:, content: "Group preview")
    }
    sign_in viewer

    [ false, true ].each do |edited|
      posts.each_value { |post| post.update!(content: "#{post.content} edited") } if edited
      get_published_discovery
      page = Nokogiri::HTML(response.body)
      posts.each do |section, post|
        key = edited ? "edited_at" : "created_at"
        timestamp = edited ? post.content_edited_at : post.created_at
        expect(page.css("#discovery_#{section} time").map(&:text)).to eq([
          I18n.t("jjaeks.meta.#{key}", time: I18n.l(timestamp, format: :short))
        ])
      end
    end
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
    latest = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: writer, group:, content: "LATEST_GROUP_POST")
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
