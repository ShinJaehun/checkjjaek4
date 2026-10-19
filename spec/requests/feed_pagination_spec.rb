require "rails_helper"

RSpec.describe "Feed pagination", type: :request do
  let(:viewer) { User.create!(name: "Page reader", email: "feed-request@example.com", password: "password123!") }
  let(:other) { User.create!(name: "Other reader", email: "feed-other@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Paginated book", authors_text: "Author") }
  let(:group) { Group.create!(name: "Page club", group_admin: viewer, lifecycle_status: :active, group_type: :public_group) }
  let(:time) { Time.zone.parse("2026-10-19 12:00:00.123456") }
  let(:navigation_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" } }
  let(:stream_headers) { { "Accept" => "text/vnd.turbo-stream.html", "X-Feed-Pagination" => "true" } }

  def path_for(location)
    case location
    when :home then root_path
    when :profile then user_path(viewer)
    when :group_activity then groups_path
    when :group then group_path(group)
    when :book then book_path(book)
    when :group_book then book_path(book, group_id: group.id)
    end
  end

  def page_document
    Nokogiri::HTML(response.body)
  end

  def card_ids
    page_document.css("#feed-items > article, turbo-stream[action='append'][target='feed-items'] template > article").map { |card| card["id"] }
  end

  def next_url
    page_document.at_css("#feed-pagination a")&.[]("href")
  end

  %i[home profile group_activity group book group_book].each do |location|
    it "renders a full HTML #{location} page unless a cursor and explicit stream request are both supplied" do
      viewer.bookshelf_entries.create!(book:) if %i[book group_book].include?(location)
      attributes = {}
      attributes[:group] = group if %i[group_activity group group_book].include?(location)
      attributes[:book] = book if %i[book group_book].include?(location)
      posts = Array.new(21) do |index|
        viewer.jjaeks.create!(**attributes, content: "NAVIGATION_POST_#{index}", created_at: time)
      end.reverse
      sign_in viewer

      # Turbo form redirects retain a stream-preferring Accept header. The
      # pagination header alone must not turn an initial visit into an append.
      [ {}, navigation_headers, stream_headers ].each do |headers|
        get path_for(location), headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/html")
        expect(page_document.at_css("html body header")).to be_present
        expect(page_document.css("turbo-stream")).to be_empty
        expect(card_ids).to eq(posts.first(20).map { |post| "jjaek_#{post.id}" })
        if %i[home group book group_book].include?(location)
          expect(page_document.at_css("textarea[name='jjaek[content]']")).to be_present
        end
      end

      url = next_url
      # A cursor also supports ordinary navigation / the no-JavaScript link.
      get url, headers: navigation_headers
      expect(response.media_type).to eq("text/html")
      expect(page_document.at_css("html body header")).to be_present
      expect(page_document.css("turbo-stream")).to be_empty
      expect(card_ids).to eq([ "jjaek_#{posts.last.id}" ])

      get url, headers: stream_headers
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(card_ids).to eq([ "jjaek_#{posts.last.id}" ])
      expect(page_document.css("turbo-stream").map { |node| [ node["action"], node["target"] ] })
        .to eq([ %w[append feed-items], %w[replace feed-pagination] ])
      expect(page_document.at_css("header, textarea[name='jjaek[content]']")).to be_nil
    end
  end

  it "follows a Turbo book-posting redirect to the full group page and its writing form" do
    viewer.bookshelf_entries.create!(book:)
    sign_in viewer

    expect {
      post jjaeks_path, params: {
        book_post_destination: "group",
        jjaek: { book_id: book.id, group_id: group.id, content: "REDIRECTED_BOOK_POST" }
      }, headers: navigation_headers
    }.to change(Jjaek, :count).by(1)
    expect(response).to redirect_to(group_path(group))
    follow_redirect!(headers: navigation_headers)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(page_document.at_css("html body header")).to be_present
    expect(page_document.at_css("form[action='#{group_jjaeks_path(group)}'] textarea[name='jjaek[content]']")).to be_present
    expect(page_document.css("turbo-stream")).to be_empty
    expect(response.body).to include("REDIRECTED_BOOK_POST")
  end

  it "follows a Turbo book-registration redirect to the full book page and its writing form" do
    sign_in viewer

    expect {
      post bookshelf_entries_path, params: { book_id: book.id, group_id: group.id }, headers: navigation_headers
    }.to change(BookshelfEntry, :count).by(1)
    expect(response).to redirect_to(book_path(book, group_id: group.id))
    follow_redirect!(headers: navigation_headers)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(page_document.at_css("html body header")).to be_present
    expect(page_document.at_css("form[action='#{jjaeks_path}'] textarea[name='jjaek[content]']")).to be_present
    expect(page_document.css("turbo-stream")).to be_empty
    expect(page_document.at_css("input[name='book_post_destination'][checked]")["value"]).to eq("group")
  end

  %i[group_activity group book group_book].each do |location|
    context "on #{location}" do
      it "renders twenty cards, then only the remaining cards and loading information" do
        viewer.bookshelf_entries.create!(book:) if location == :group_book
        attributes = {}
        attributes[:group] = group if %i[group_activity group group_book].include?(location)
        attributes[:book] = book if %i[book group_book].include?(location)
        posts = Array.new(23) do |index|
          viewer.jjaeks.create!(**attributes, content: "PAGE_CARD_#{index}", created_at: time)
        end.reverse
        # An unreadable personal post must remain excluded even in later pages.
        other.jjaeks.create!(book:, visibility: :private_jjaek, content: "PRIVATE_PAGE_BODY", created_at: time - 1.second)
        sign_in viewer

        loaded_posts = 0
        subscriber = lambda do |*args|
          payload = args.last
          loaded_posts += payload[:record_count] if payload[:class_name] == "Jjaek"
        end
        origin = book_search_path(query: "pagination") if %i[book group_book].include?(location)
        ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
          get path_for(location), params: { return_to: origin }.compact
        end
        expect(loaded_posts).to eq(21)
        expect(response).to have_http_status(:ok)
        expect(card_ids).to eq(posts.first(20).map { |post| "jjaek_#{post.id}" })
        url = next_url
        expect(url).to be_present
        expect(URI.decode_www_form(URI.parse(url).query).to_h["return_to"]).to eq(origin) if origin
        expect(URI.decode_www_form(URI.parse(url).query).to_h["group_id"]).to eq(group.id.to_s) if location == :group_book

        get url, headers: stream_headers
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(card_ids).to eq(posts.last(3).map { |post| "jjaek_#{post.id}" })
        expect(page_document.css("turbo-stream").map { |node| node["target"] }).to eq(%w[feed-items feed-pagination])
        expect(page_document.at_css("header, h1, textarea[name='jjaek[content]']")).to be_nil
        expect(page_document.at_css("[data-feed-end]")).to be_present
        expect(next_url).to be_nil
        expect(response.body).not_to include("PRIVATE_PAGE_BODY")

        get url
        expect(response.media_type).to eq("text/html")
        expect(card_ids).to eq(posts.last(3).map { |post| "jjaek_#{post.id}" })
      end
    end
  end

  %i[home profile].each do |location|
    it "paginates mixed Jjaek and BookActivity on #{location} with deterministic ties" do
      posts = Array.new(13) { |index| viewer.jjaeks.create!(content: "MIXED_POST_#{index}", created_at: time) }.reverse
      entry = viewer.bookshelf_entries.create!(book:)
      activities = Array.new(13) do
        entry.book_activities.create!(user: viewer, book:, action: :added_to_shelf, created_at: time)
      end.reverse
      sign_in viewer

      get(location == :home ? root_path : user_path(viewer))
      expected = posts.map { |post| "jjaek_#{post.id}" } + activities.map { |item| "book_activity_#{item.id}" }
      expect(card_ids).to eq(expected.first(20))
      url = next_url
      get url, headers: stream_headers

      expect(card_ids).to eq(expected.drop(20))
      expect(next_url).to be_nil
      expect(page_document.at_css("[data-feed-end]")).to be_present
      expect(page_document.css("turbo-stream").size).to eq(2)
    end
  end

  it "returns a bad request for invalid cursors in HTML and Turbo without exposing content" do
    viewer.jjaeks.create!(content: "DO_NOT_RENDER_FOR_BAD_CURSOR")
    sign_in viewer
    [ {}, stream_headers ].each do |headers|
      get root_path, params: { cursor: "modified" }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.body).not_to include("DO_NOT_RENDER_FOR_BAD_CURSOR")
    end
  end

  it "keeps an empty feed and a valid cursor past the end terminal" do
    sign_in viewer
    get root_path
    expect(card_ids).to be_empty
    expect(next_url).to be_nil
    expect(response.body).to include(I18n.t("home.empty_feed"))
    expect(page_document.at_css("[data-infinite-scroll-target='error']")).to be_nil

    posts = Array.new(21) { |index| viewer.jjaeks.create!(content: "ENDING_#{index}", created_at: time) }
    get root_path
    url = next_url
    posts.first.destroy!
    get url, headers: stream_headers
    expect(card_ids).to be_empty
    expect(page_document.at_css("[data-feed-end]")).to be_present
    expect(next_url).to be_nil
  end

  it "rechecks following and profile visibility when a signed cursor is replayed" do
    viewer.active_follows.create!(followee: other)
    posts = Array.new(23) { |index| other.jjaeks.create!(content: "FOLLOWED_PAGE_#{index}", created_at: time) }
    sign_in viewer
    get root_path
    url = next_url
    viewer.active_follows.destroy_all
    posts.each { |post| post.update!(visibility: :private_jjaek) }

    get url, headers: stream_headers
    expect(card_ids).to be_empty
    expect(response.body).not_to include("FOLLOWED_PAGE_")
    cursor = URI.decode_www_form(URI.parse(url).query).to_h.fetch("cursor")
    get user_path(other), params: { cursor: }, headers: stream_headers
    expect(card_ids).to be_empty
    expect(response.body).not_to include("FOLLOWED_PAGE_")
  end

  it "rechecks membership on both group feeds and group book detail for subsequent requests" do
    private_group = Group.create!(name: "Private page club", group_admin: other, lifecycle_status: :active, group_type: :private_group)
    membership = private_group.group_memberships.create!(user: viewer, status: :active)
    viewer.bookshelf_entries.create!(book:)
    23.times { |index| other.jjaeks.create!(group: private_group, book:, content: "PRIVATE_GROUP_PAGE_#{index}", created_at: time) }
    sign_in viewer
    get groups_path
    index_url = next_url
    get group_path(private_group)
    group_url = next_url
    get book_path(book, group_id: private_group.id)
    book_url = next_url
    membership.destroy!

    get index_url, headers: stream_headers
    expect(card_ids).to be_empty
    get group_url, headers: stream_headers
    expect(response).to redirect_to(groups_path)
    expect(card_ids).to be_empty

    get book_url, headers: stream_headers
    expect(response).to have_http_status(:not_found)
    expect(card_ids).to be_empty
  end

  it "rechecks the current bookshelf visibility for later BookActivity pages" do
    viewer.active_follows.create!(followee: other)
    BookFriendship.create!(requester: viewer, addressee: other, status: :accepted)
    shelf = other.bookshelves.create!(name: "Activity page shelf", visibility: :public)
    entry = other.bookshelf_entries.create!(book:, bookshelf: shelf)
    21.times do
      entry.book_activities.create!(user: other, book:, action: :added_to_shelf, created_at: time)
    end
    sign_in viewer
    get root_path
    expect(card_ids.size).to eq(20)
    url = next_url
    shelf.update!(visibility: :private)

    get url, headers: stream_headers
    expect(card_ids).to be_empty
    expect(response.body).not_to include(book.title, other.name)
  end

  it "keeps moderation, reading state, avatars and card actions on later pages" do
    entry = viewer.bookshelf_entries.create!(book:, status: :reading)
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      viewer.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end
    post = viewer.jjaeks.create!(book:, content: "LAST_PAGE_BOOK_POST", created_at: time - 1.second)
    hidden = viewer.jjaeks.create!(content: "LAST_PAGE_HIDDEN_POST", created_at: time - 2.seconds)
    moderator = User.create!(name: "Moderator", email: "feed-moderator@example.com", password: "password123!", global_admin: true)
    Jjaeks::Hide.new(hidden, actor: moderator, public_reason: "other").call!
    other.jjaeks.create!(quoted_jjaek: post, content: "READABLE_REQUOTE", visibility: :public_jjaek)
    20.times { |index| viewer.jjaeks.create!(content: "NEWER_#{index}", created_at: time) }
    sign_in viewer
    get root_path
    get next_url, headers: stream_headers

    card = page_document.at_css("article#jjaek_#{post.id}")
    expect(card.text).to include(post.content, I18n.t("bookshelf_entries.statuses.#{entry.status}"), I18n.t("jjaeks.meta.requotes", count: 1))
    expect(card.at_css("img[src*='/rails/active_storage/representations/']")).to be_present
    expect(card.at_css("form[action='#{jjaek_like_path(post)}']")).to be_present
    expect(card.at_css("a[href*='#{jjaek_comments_path(post)}']")).to be_present
    expect(page_document.at_css("article#jjaek_#{hidden.id}")["class"]).to include("border-red-200")
    expect(response.body).to include("LAST_PAGE_HIDDEN_POST")
  end
end
