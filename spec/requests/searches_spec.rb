require "rails_helper"

RSpec.describe "Unified search", type: :request do
  let(:viewer) { User.create!(name: "검색자", email: "search-viewer@example.com", password: "password123!") }
  let(:writer) { User.create!(name: "기록 작성자", email: "search-writer@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "검색 테스트 책") }

  def search_section(type)
    Nokogiri::HTML(response.body).at_css("section[aria-labelledby='search-#{type}-title']")
  end

  it "requires sign in" do
    get search_path, params: { q: "독서" }

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows an input prompt without results for missing or whitespace-only queries" do
    sign_in viewer

    [ nil, "  \t " ].each do |query|
      get search_path, params: { q: query }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unified_search.prompt"))
      expect(search_section("users")).to be_nil
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("form[action='#{search_path}']")["method"]).to eq("get")
      expect(page.at_css("a[href='#{search_path}']").text).to eq(I18n.t("unified_search.nav"))
    end
  end

  it "shows an empty result message for every type when nothing matches" do
    sign_in viewer
    get search_path, params: { q: "존재하지않는검색어" }

    %w[users jjaeks book_jjaeks groups].each do |type|
      expect(search_section(type).text).to include(I18n.t("unified_search.no_results", query: "존재하지않는검색어"))
      expect(search_section(type).css("article")).to be_empty
    end
  end

  describe "result types" do
    let!(:matched_user) { User.create!(name: "한글 독자", handle: "hangul_reader", email: "hangul@example.com", password: "password123!") }
    let!(:general_post) { writer.jjaeks.create!(content: "한글 일반 짹") }
    let!(:book_post) { writer.jjaeks.create!(book:, content: "한글 책짹") }
    let!(:group) { Group.create!(group_admin: writer, name: "한글 모임", lifecycle_status: :active) }

    before { sign_in viewer }

    it "finds Korean substrings in all four types and links to existing details" do
      get search_path, params: { q: "  한글  " }

      expect(search_section("users").text).to include(matched_user.name, "@hangul_reader")
      expect(search_section("users").at_css("article a")["href"]).to eq(user_path(matched_user))
      expect(search_section("groups").at_css("article a")["href"]).to eq(group_path(group))
      { "jjaeks" => general_post, "book_jjaeks" => book_post }.each do |type, post|
        section = search_section(type)
        expect(section.text).to include(writer.name, post.content)
        expect(section.at_css("a[href='#{jjaek_path(post, return_to: search_path(q: '한글', type: 'all', per_page: 30))}']")).to be_present
        expect(section.at_css("a[href='#{user_path(writer)}']")).to be_present
      end
      expect(search_section("book_jjaeks").text).to include(book.title)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[name='q']")["value"]).to eq("한글")
      expect(page.css("nav[aria-label] a[aria-current='page']").map(&:text)).to include(I18n.t("unified_search.types.all"))
    end

    %w[users jjaeks book_jjaeks groups].each do |type|
      it "shows only #{type} on its individual tab and preserves the search term" do
        get search_path, params: { q: "한글", type: }

        expect(search_section(type)).to be_present
        (%w[users jjaeks book_jjaeks groups] - [ type ]).each do |other_type|
          expect(search_section(other_type)).to be_nil
        end
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("input[name='type']")["value"]).to eq(type)
        expect(page.at_css("a[aria-current='page']")["href"]).to eq(search_path(q: "한글", type:, per_page: 30))
      end
    end

    it "falls back to all types for an unknown type" do
      get search_path, params: { q: "한글", type: "comments" }

      %w[users jjaeks book_jjaeks groups].each do |type|
        expect(search_section(type)).to be_present
      end
    end
  end

  it "searches public handles case-insensitively but neither searches nor displays email" do
    reader = User.create!(name: "공개이름", handle: "public_reader", email: "private-address@example.com", password: "password123!")
    sign_in viewer

    get search_path, params: { q: "PUBLIC_READ", type: "users" }
    expect(search_section("users").text).to include(reader.name, "@public_reader")
    expect(response.body).not_to include(reader.email)

    get search_path, params: { q: "private-address", type: "users" }
    expect(search_section("users").css("article")).to be_empty
    expect(response.body).not_to include(reader.name, reader.email)
  end

  it "does not discover withdrawn users" do
    writer.update_columns(withdrawn_at: Time.current)
    sign_in viewer
    get search_path, params: { q: writer.name, type: "users" }

    expect(search_section("users").css("article")).to be_empty
  end

  it "shows user avatars, public counts, and simultaneous relationships without badges for self or pending friends" do
    viewer.update!(name: "관계검색 본인")
    writer.update!(name: "관계검색 책친구")
    pending = User.create!(name: "관계검색 요청중", email: "search-pending@example.com", password: "password123!")
    BookFriendship.create!(requester: writer, addressee: viewer, status: :accepted)
    BookFriendship.create!(requester: viewer, addressee: pending, status: :pending)
    Follow.create!(follower: viewer, followee: writer)
    Follow.create!(follower: writer, followee: viewer)
    sign_in viewer
    get search_path, params: { q: "관계검색", type: "users" }

    cards = search_section("users").css("article")
    friend_card = cards.find { |card| card.at_css("a")["href"] == user_path(writer) }
    expect(friend_card.at_css("img")["alt"]).to eq(writer.name)
    expect(friend_card.text).to include(I18n.t("users.profile.stats", followers: 1, following: 1))
    expect(friend_card.css("[data-search-user-relationships] span").map(&:text))
      .to eq([ "책친구", "내가 소식 받는 사람", "내 소식을 받는 사람" ])
    cards.reject { |card| card == friend_card }.each do |card|
      expect(card.at_css("[data-search-user-relationships]")).to be_nil
    end
    expect(search_section("users").css("form")).to be_empty
  end

  it "distinguishes outgoing and incoming follows without showing unrelated relationship badges" do
    writer.update!(name: "방향검색 내가받음")
    follower = User.create!(name: "방향검색 상대가받음", email: "search-incoming@example.com", password: "password123!")
    Follow.create!(follower: viewer, followee: writer)
    Follow.create!(follower:, followee: viewer)
    sign_in viewer
    get search_path, params: { q: "방향검색", type: "users" }

    cards = search_section("users").css("article")
    outgoing = cards.find { |card| card.at_css("a")["href"] == user_path(writer) }
    incoming = cards.find { |card| card.at_css("a")["href"] == user_path(follower) }
    expect(outgoing.css("[data-search-user-relationships] span").map(&:text)).to eq([ "내가 소식 받는 사람" ])
    expect(incoming.css("[data-search-user-relationships] span").map(&:text)).to eq([ "내 소식을 받는 사람" ])
  end

  it "reuses read-only post cards with author, visibility, cover, book information, and reading badges" do
    book.update!(thumbnail: "https://example.com/search-cover.jpg", authors_text: "카드 저자")
    entry = viewer.bookshelf_entries.create!(book:, status: :reading)
    sticker = StickerDefinition.create!(key: "loved_it", name: "Loved it")
    entry.sticker_definitions << sticker
    post = viewer.jjaeks.create!(book:, content: "카드검색 본문", visibility: :book_friends)
    sign_in viewer
    get search_path, params: { q: "카드검색", type: "book_jjaeks" }

    card = search_section("book_jjaeks").at_css("article")
    expect(card.at_css("img[alt='#{viewer.name}']")).to be_present
    expect(card.at_css("img[alt='#{book.title}']")["src"]).to eq(book.thumbnail)
    expect(card.text).to include(viewer.name, post.content, book.title, book.authors_text,
                               I18n.t("jjaeks.visibility.book_friends"),
                               I18n.t("jjaeks.meta.created_at", time: I18n.l(post.created_at, format: :short)))
    expect(card.text).to include(I18n.t("jjaeks.contexts.book_html", author_name: viewer.name))
    expect(card.at_css("[data-reading-status='reading']")).to be_present
    expect(card.at_css("[data-reading-sticker='loved_it']")).to be_present
    expect(card.css("form")).to be_empty
    expect(card.at_css("a[href='#{edit_jjaek_path(post)}']")).to be_nil
    expect(card.at_css("a[href*='/comments'], a[href*='/requotes']")).to be_nil
  end

  it "keeps reading metadata on public book-post cards restricted to accepted book friends" do
    entry = writer.bookshelf_entries.create!(book:, status: :finished)
    entry.bookshelf.update!(visibility: :public)
    writer.jjaeks.create!(book:, content: "독서카드검색")
    sign_in viewer
    get search_path, params: { q: "독서카드검색", type: "book_jjaeks" }
    expect(search_section("book_jjaeks").at_css("[data-current-reading-state]")).to be_nil

    BookFriendship.create!(requester: viewer, addressee: writer, status: :accepted)
    get search_path, params: { q: "독서카드검색", type: "book_jjaeks" }
    expect(search_section("book_jjaeks").at_css("[data-reading-status='finished']")).to be_present
  end

  [ "%", "_", "\\", "' OR 1=1 --" ].each do |term|
    it "treats #{term.inspect} as literal search text" do
      match = writer.jjaeks.create!(content: "記号 #{term} を含む")
      other = writer.jjaeks.create!(content: "UNRELATED CONTENT")
      sign_in viewer
      get search_path, params: { q: term, type: "jjaeks" }

      expect(search_section("jjaeks").text).to include(match.content)
      expect(search_section("jjaeks").text).not_to include(other.content)
      expect(search_section("jjaeks").css("article").size).to eq(1)
    end
  end

  it "escapes user content in both the query and result previews" do
    post = writer.jjaeks.create!(content: '<script>alert("search")</script>')
    sign_in viewer
    get search_path, params: { q: "<script>", type: "jjaeks" }

    section = search_section("jjaeks")
    expect(section.text).to include(post.content)
    expect(section.css("script")).to be_empty
  end

  it "does not search comments or book titles" do
    parent = writer.jjaeks.create!(content: "Parent content")
    parent.comments.create!(user: writer, content: "댓글전용검색어")
    writer.jjaeks.create!(book:, content: "Unrelated book post")
    sign_in viewer

    [ "댓글전용검색어", book.title ].each do |term|
      get search_path, params: { q: term }
      expect(search_section("jjaeks").css("article")).to be_empty
      expect(search_section("book_jjaeks").css("article")).to be_empty
    end
  end

  %w[jjaeks book_jjaeks].each do |type|
    describe "#{type} visibility" do
      let(:post_book) { type == "book_jjaeks" ? book : nil }

      it "finds public and own private posts while hiding others' private posts and previews" do
        public_post = viewer.jjaeks.create!(book: post_book, content: "권한검색 PUBLIC")
        own_post = viewer.jjaeks.create!(book: post_book, content: "권한검색 OWN_PRIVATE", visibility: :private_jjaek)
        secret_post = writer.jjaeks.create!(book: post_book, content: "권한검색 SECRET_PRIVATE", visibility: :private_jjaek)
        sign_in viewer
        get search_path, params: { q: "권한검색", type: }

        expect(search_section(type).text).to include(public_post.content, own_post.content)
        expect(response.body).not_to include(secret_post.content, writer.name, jjaek_path(secret_post))
      end

      it "requires accepted book friendship, rather than following or a pending request" do
        post = writer.jjaeks.create!(book: post_book, content: "친구검색 FRIEND_ONLY", visibility: :book_friends)
        Follow.create!(follower: viewer, followee: writer)
        friendship = BookFriendship.create!(requester: viewer, addressee: writer, status: :pending)
        sign_in viewer

        get search_path, params: { q: "친구검색" }
        expect(response.body).not_to include(post.content, writer.name, jjaek_path(post))

        friendship.update!(status: :accepted)
        get search_path, params: { q: "친구검색", type: }
        expect(search_section(type).text).to include(post.content, writer.name)

        friendship.destroy!
        get search_path, params: { q: "친구검색", type: }
        expect(response.body).not_to include(post.content, writer.name, jjaek_path(post))
      end

      it "excludes hidden and deleted posts even when the viewer is their author" do
        hidden = viewer.jjaeks.create!(book: post_book, content: "운영검색 HIDDEN")
        hidden.update_columns(hidden_at: Time.current)
        deleted = viewer.jjaeks.create!(book: post_book, content: "운영검색 DELETED")
        deleted.update_columns(deleted_at: Time.current)
        sign_in viewer
        get search_path, params: { q: "운영검색", type: }

        expect(search_section(type).css("article")).to be_empty
        expect(response.body).not_to include(hidden.content, deleted.content)
      end
    end
  end

  it "does not add an operational admin bypass for personal private content" do
    viewer.update!(global_admin: true)
    secret = writer.jjaeks.create!(content: "관리검색 PRIVATE", visibility: :private_jjaek)
    sign_in viewer
    get search_path, params: { q: "관리검색" }

    expect(response.body).not_to include(secret.content, writer.name, jjaek_path(secret))
  end

  it "preserves the existing recipient access to a profile-context book-friends post" do
    post = writer.jjaeks.create!(target_user: viewer, content: "받는이검색", visibility: :book_friends)
    sign_in viewer
    get search_path, params: { q: "받는이검색", type: "jjaeks" }

    card = search_section("jjaeks").at_css("article")
    expect(card.text).to include(post.content,
                                 I18n.t("jjaeks.contexts.profile_html", author_name: writer.name, target_user_name: viewer.name))
    expect(card.at_css("a[href='#{user_path(viewer)}']")).to be_present
  end

  it "discovers private group names without descriptions, members, or internal content" do
    group = Group.create!(group_admin: writer, name: "비밀검색 모임", description: "PRIVATE_DESCRIPTION",
                          lifecycle_status: :active, group_type: :private_group)
    post = writer.jjaeks.create!(group:, content: "비밀검색 INTERNAL_POST")
    book_post = writer.jjaeks.create!(group:, book:, content: "비밀검색 INTERNAL_BOOK_POST")
    sign_in viewer
    get search_path, params: { q: "비밀검색" }

    expect(search_section("groups").text).to include(group.name)
    expect(search_section("groups").at_css("article a")["href"]).to eq(group_path(group))
    expect(search_section("groups").at_css("[data-group-type='private_group']")).to be_present
    expect(search_section("groups").at_css("[data-group-members]")).to be_nil
    expect(search_section("groups").at_css("img")).to be_nil
    expect(response.body).not_to include(group.description, writer.name, post.content, book_post.content, book.title)

    get group_path(group)
    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("groups.alerts.not_found_or_inaccessible"))
    expect(response.body).not_to include(group.description, post.content, book_post.content)
    get jjaek_path(post)
    expect(response).to have_http_status(:not_found)
  end

  it "reuses private group cards with administrator and bounded member previews for authorized members" do
    group = Group.create!(group_admin: writer, name: "회원카드검색", lifecycle_status: :active, group_type: :private_group)
    members = [ viewer ] + 3.times.map do |index|
      User.create!(name: "미리보기 회원 #{index}", email: "search-member#{index}@example.com", password: "password123!")
    end
    members.each { |member| group.group_memberships.create!(user: member, status: :active) }
    sign_in viewer
    get search_path, params: { q: "회원카드검색", type: "groups" }

    card = search_section("groups").at_css("article")
    expect(card.at_css("[data-group-type='private_group']")).to be_present
    expect(card.at_css("img[alt='#{writer.name}']")).to be_present
    expect(card.at_css("[data-field='active-member-count']").text).to eq(I18n.t("groups.active_member_count", count: 4))
    expect(card.css("[data-member-preview] a").map { |link| link["href"] }).to eq(members.first(3).map { |member| user_path(member) })
    expect(card.text).not_to include(members.last.name)
  end

  it "shows the existing public profile information for public and approval groups without exposing their content" do
    member = User.create!(name: "공개 회원", email: "search-public-member@example.com", password: "password123!")
    %i[public_group approval_group].each do |group_type|
      group = Group.create!(group_admin: writer, name: "공개카드검색 #{group_type}", lifecycle_status: :active, group_type:)
      group.group_memberships.create!(user: member, status: :active)
      writer.jjaeks.create!(group:, content: "NOT_A_GROUP_NAME_RESULT")
    end
    sign_in viewer
    get search_path, params: { q: "공개카드검색", type: "groups" }

    cards = search_section("groups").css("article")
    expect(cards.size).to eq(2)
    cards.each do |card|
      expect(card.at_css("img[alt='#{writer.name}']")).to be_present
      expect(card.at_css("[data-field='active-member-count']").text).to eq(I18n.t("groups.active_member_count", count: 1))
      expect(card.at_css("[data-member-preview] img")["alt"]).to eq(member.name)
      expect(card.text).not_to include("NOT_A_GROUP_NAME_RESULT")
    end
  end

  %i[public_group approval_group private_group].each do |group_type|
    it "keeps #{group_type} content within current membership and lifecycle access" do
      group = Group.create!(group_admin: writer, name: "Group #{group_type}", lifecycle_status: :active, group_type:)
      post = writer.jjaeks.create!(group:, content: "동아리검색 GENERAL")
      book_post = writer.jjaeks.create!(group:, book:, content: "동아리검색 BOOK")
      membership = group.group_memberships.create!(user: viewer, status: :invited)
      sign_in viewer

      get search_path, params: { q: "동아리검색" }
      if group_type == :public_group
        expect(response.body).to include(post.content, book_post.content)
      else
        expect(response.body).not_to include(post.content, book_post.content, writer.name)
      end

      membership.update!(status: :active)
      get search_path, params: { q: "동아리검색" }
      expect(response.body).to include(post.content, book_post.content)
      group_label = "#{I18n.t('jjaeks.contexts.group_badge')} #{group.name}"
      expect(search_section("jjaeks").at_css("article").text.squish)
        .to include(I18n.t("jjaeks.contexts.group_general_html", author_name: writer.name,
                           group_name: group_label))
      expect(search_section("book_jjaeks").at_css("article").text.squish)
        .to include(I18n.t("jjaeks.contexts.group_book_html", author_name: writer.name,
                           group_name: group_label, book_title: book.title))

      group.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "독서 모임 종료")
      get search_path, params: { q: "동아리검색" }
      expect(response.body).to include(post.content, book_post.content)

      membership.destroy!
      get search_path, params: { q: "동아리검색" }
      expect(response.body).not_to include(post.content, book_post.content, writer.name)
    end
  end

  it "does not discover inactive or pending groups outside the existing group scope" do
    group = Group.create!(group_admin: writer, name: "종료검색 모임", lifecycle_status: :inactive,
                          closed_at: Time.current, closure_reason: "독서 모임 종료", group_type: :private_group)
    pending = Group.create!(group_admin: writer, name: "종료검색 신청", application_purpose: "읽기")
    sign_in viewer
    get search_path, params: { q: "종료검색", type: "groups" }

    expect(search_section("groups").css("article")).to be_empty

    sign_in writer
    get search_path, params: { q: "종료검색", type: "groups" }
    expect(search_section("groups").text).to include(group.name, pending.name)
  end

  it "searches a requote's own body while rechecking its nonmatching source visibility" do
    source = writer.jjaeks.create!(content: "Original without search term")
    requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "인용검색 OWN_BODY")
    sign_in viewer
    get search_path, params: { q: "인용검색", type: "jjaeks" }

    expect(search_section("jjaeks").text).to include(requote.content)
    expect(search_section("jjaeks").text).not_to include(source.content)
    expect(search_section("jjaeks").at_css("article").text.squish)
      .to include(I18n.t("jjaeks.contexts.requote_html", author_name: viewer.name,
                         quoted_user_name: writer.name, quoted_context_label: I18n.t("jjaeks.contexts.quoted_general")))

    source.update!(visibility: :private_jjaek)
    get search_path, params: { q: "인용검색", type: "jjaeks" }
    expect(response.body).not_to include(requote.content, jjaek_path(requote))

    source.update!(visibility: :public_jjaek)
    source.update_columns(hidden_at: Time.current)
    get search_path, params: { q: "인용검색" }
    expect(response.body).not_to include(requote.content, jjaek_path(requote))
  end

  it "keeps deleted-source personal requotes author-only and group requotes within their group" do
    group = Group.create!(group_admin: writer, name: "인용 동아리", lifecycle_status: :active, group_type: :private_group)
    source = writer.jjaeks.create!(content: "Original content")
    personal = writer.jjaeks.create!(quoted_jjaek: source, content: "삭제인용 PERSONAL")
    shared = writer.jjaeks.create!(group:, quoted_jjaek: source, content: "삭제인용 GROUP")
    source.destroy_or_tombstone!
    sign_in viewer

    get search_path, params: { q: "삭제인용" }
    expect(response.body).not_to include(personal.content, shared.content)

    group.group_memberships.create!(user: viewer, status: :active)
    get search_path, params: { q: "삭제인용" }
    expect(response.body).to include(shared.content)
    expect(response.body).not_to include(personal.content)

    sign_in writer
    get search_path, params: { q: "삭제인용" }
    expect(response.body).to include(personal.content, shared.content)
  end

  it "bounds all-type previews and links each section to its full results" do
    6.times do |index|
      User.create!(name: "미리보기 독자 #{index}", email: "preview#{index}@example.com", password: "password123!")
      writer.jjaeks.create!(content: "미리보기 일반 #{index}")
      writer.jjaeks.create!(book:, content: "미리보기 책짹 #{index}")
      Group.create!(group_admin: writer, name: "미리보기 모임 #{index}", lifecycle_status: :active)
    end
    sign_in viewer
    get search_path, params: { q: "미리보기", per_page: 50, page: 2 }

    %w[users jjaeks book_jjaeks groups].each do |type|
      section = search_section(type)
      expect(section.css("article").size).to eq(5)
      expect(section.at_css("a[href='#{search_path(q: '미리보기', type:, per_page: 50)}']")).to be_present
    end
    expect(Nokogiri::HTML(response.body).at_css("select[name='per_page']")).to be_nil
  end

  it "paginates in stable newest-first order while preserving the query and type" do
    timestamp = Time.current
    posts = 31.times.map { |index| writer.jjaeks.create!(content: "페이지검색 #{index}", created_at: timestamp) }
    sign_in viewer
    get search_path, params: { q: "페이지검색", type: "jjaeks" }

    section = search_section("jjaeks")
    expect(section.css("article").size).to eq(30)
    cards = section.css("article")
    expect(cards.map { |card| URI.parse(card.css("a").last["href"]).path }).to eq(posts.reverse.first(30).map { |post| jjaek_path(post) })
    cards.zip(posts.reverse.first(30)).each do |card, post|
      expect(card.text).to include(post.content)
    end
    page = Nokogiri::HTML(response.body)
    next_link = page.css("a").find { |link| link.text == I18n.t("pagination.next") }
    expect(Rack::Utils.parse_query(URI.parse(next_link["href"]).query))
      .to eq("q" => "페이지검색", "type" => "jjaeks", "per_page" => "30", "page" => "2")

    get next_link["href"]
    expect(search_section("jjaeks").css("article").size).to eq(1)
    expect(search_section("jjaeks").text).to include(posts.first.content)
    expect(Nokogiri::HTML(response.body).css("a").map(&:text)).to include(I18n.t("pagination.previous"))
  end

  it "supports 50 and 100 results per page while preserving URL state and resetting the size form to page one" do
    101.times { |index| writer.jjaeks.create!(content: "개수검색 #{index}") }
    sign_in viewer

    [ 50, 100 ].each do |size|
      get search_path, params: { q: "개수검색", type: "jjaeks", per_page: size }
      expect(search_section("jjaeks").css("article").size).to eq(size)
      page = Nokogiri::HTML(response.body)
      next_link = page.css("a").find { |link| link.text == I18n.t("pagination.next") }
      expect(Rack::Utils.parse_query(URI.parse(next_link["href"]).query))
        .to eq("q" => "개수검색", "type" => "jjaeks", "per_page" => size.to_s, "page" => "2")

      get next_link["href"]
      expect(search_section("jjaeks").css("article").size).to eq([ 101 - size, size ].min)
      page = Nokogiri::HTML(response.body)
      form = page.at_css("form[action='#{search_path}']")
      select = form.at_css("select[name='per_page']")
      expect(select.css("option").map { |option| option["value"] }).to eq(%w[30 50 100])
      expect(select.at_css("option[selected]")["value"]).to eq(size.to_s)
      expect(select["data-action"]).to eq("change->page-size#submit")
      expect(form.at_css("input[name='q']")["value"]).to eq("개수검색")
      expect(form.at_css("input[name='type']")["value"]).to eq("jjaeks")
      expect(form.at_css("[name='page']")).to be_nil
      page.css("main nav[aria-label] a").each do |link|
        expect(Rack::Utils.parse_query(URI.parse(link["href"]).query))
          .to include("q" => "개수검색", "per_page" => size.to_s)
        expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)).not_to have_key("page")
      end
    end
  end

  it "normalizes unsupported page sizes in the selector and search links" do
    writer.jjaeks.create!(content: "기본개수검색")
    sign_in viewer
    get search_path, params: { q: "기본개수검색", type: "jjaeks", per_page: 999 }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("select[name='per_page'] option[selected]")["value"]).to eq("30")
    page.css("main nav[aria-label] a").each do |link|
      expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["per_page"]).to eq("30")
    end
  end

  it "normalizes invalid and out-of-range page numbers" do
    post = writer.jjaeks.create!(content: "범위검색")
    sign_in viewer

    [ "invalid", "-2", "0", "99999999" ].each do |page|
      get search_path, params: { q: "범위검색", type: "jjaeks", page: }
      expect(response).to have_http_status(:ok)
      expect(search_section("jjaeks").text).to include(post.content)
      expect(search_section("jjaeks").css("article").size).to eq(1)
    end
  end

  it "returns from post details to the search query, type, and page without forwarding unrelated parameters" do
    writer.jjaeks.create!(content: "돌아가기검색")
    sign_in viewer
    get search_path, params: { q: "돌아가기검색", type: "jjaeks", per_page: 50, page: 1, unsafe: "not-forwarded" }
    detail_link = search_section("jjaeks").css("article a").last["href"]

    get detail_link

    expect(response).to have_http_status(:ok)
    back_link = Nokogiri::HTML(response.body).at_css("a[data-jjaek-back]")
    origin = URI.parse(back_link["href"])
    expect(origin.path).to eq(search_path)
    expect(Rack::Utils.parse_query(origin.query)).to eq("q" => "돌아가기검색", "type" => "jjaeks", "per_page" => "50", "page" => "1")
  end

  it "renders English search labels without missing translations" do
    sign_in viewer
    I18n.with_locale(:en) do
      get search_path, params: { q: "nomatch" }
      expect(response.body).to include("Search Bookjjaek", "Book posts", "No results found")
      expect(response.body).not_to include("translation_missing")
    end
  end

  describe "tag search" do
    before { sign_in viewer }

    it "redirects a single hashtag from the shared search field to tag mode" do
      post = writer.jjaeks.create!(content: "Input #Reading")

      get search_path, params: { q: "  #READING  ", type: "jjaeks", per_page: 50, page: 3 }
      expect(response).to redirect_to(search_path(tag: "reading", type: "jjaeks", per_page: 50))

      follow_redirect!
      expect(search_section("jjaeks").text).to include(post.content)
      expect(search_section("users")).to be_nil
      expect(search_section("groups")).to be_nil
      page = Nokogiri::HTML(response.body)
      expect(page.css("form[action='#{search_path}']").size).to eq(1)
      search_fields = page.css("form[action='#{search_path}'] input[type='search']")
      expect(search_fields.map { |field| field["name"] }).to eq([ "q" ])
      expect(search_fields.first["value"]).to eq("#reading")
      expect(search_fields.first["placeholder"]).to eq("사용자, 짹, 책짹, 동아리, #태그 검색")
    end

    it "preserves the book-post tab and resets user or group tabs for hashtag input" do
      get search_path, params: { q: "#독서_토론", type: "book_jjaeks", per_page: 50, page: 4 }
      expect(response).to redirect_to(search_path(tag: "독서_토론", type: "book_jjaeks", per_page: 50))

      %w[users groups].each do |type|
        get search_path, params: { q: "#독서_토론", type:, per_page: 100, page: 4 }
        expect(response).to redirect_to(search_path(tag: "독서_토론", type: "all", per_page: 100))
      end
    end

    it "keeps non-single hashtags in ordinary text search" do
      [ "#독서 토론", "#독서-토론", "#", "독서 #토론" ].each do |query|
        get search_path, params: { q: query, type: "jjaeks" }
        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("input[name='q']")["value"]).to eq(query)
        expect(page.at_css("nav[aria-label='#{I18n.t('unified_search.tag_scope_label')}']")).to be_nil
      end
    end

    it "uses exact tag links for posts while preserving ordinary text search" do
      exact = writer.jjaeks.create!(content: "태그검증 #우정")
      longer = writer.jjaeks.create!(content: "태그검증 #우정의힘")
      book_post = writer.jjaeks.create!(book:, content: "태그검증 #우정")
      english = writer.jjaeks.create!(content: "태그검증 #Reading")

      get search_path, params: { tag: "우정" }
      expect(search_section("jjaeks").text).to include(exact.content)
      expect(search_section("jjaeks").text).not_to include(longer.content)
      expect(search_section("book_jjaeks").text).to include(book_post.content)
      expect(search_section("users")).to be_nil
      expect(search_section("groups")).to be_nil

      get search_path, params: { tag: "READING", type: "jjaeks" }
      expect(search_section("jjaeks").text).to include(english.content)

      get search_path, params: { q: "우정", type: "jjaeks" }
      expect(search_section("jjaeks").text).to include(exact.content, longer.content)
    end

    it "reuses bounded previews and individual tab page sizes for tags" do
      6.times { |index| writer.jjaeks.create!(content: "태그목록 #{index} #목록") }

      get search_path, params: { tag: "목록" }
      expect(search_section("jjaeks").css("article").size).to eq(5)
      expect(search_section("jjaeks").at_css("a[href='#{search_path(tag: '목록', scope: 'all', type: 'jjaeks', per_page: 30)}']")).to be_present

      get search_path, params: { tag: "목록", type: "jjaeks", per_page: 50 }
      expect(search_section("jjaeks").css("article").size).to eq(6)
      expect(search_section("book_jjaeks")).to be_nil
    end

    it "filters a group scope through the existing content policy and supports all results" do
      group = Group.create!(group_admin: writer, name: "태그 동아리", group_type: :private_group, lifecycle_status: :active)
      group_post = writer.jjaeks.create!(group:, content: "그룹본문 #함께")
      next_tag_post = writer.jjaeks.create!(group:, content: "그룹다음 #다른")
      personal = writer.jjaeks.create!(content: "개인본문 #함께")

      get search_path, params: { tag: "함께", scope: "group", group_id: group.id }
      expect(response).to have_http_status(:not_found)

      sign_in viewer
      get search_path, params: { tag: "함께" }
      expect(response).to have_http_status(:ok)
      expect(search_section("jjaeks").text).to include(personal.content)
      expect(search_section("jjaeks").text).not_to include(group_post.content)

      group.group_memberships.create!(user: viewer, status: :active)
      get search_path, params: { tag: "함께", scope: "group", group_id: group.id }
      expect(search_section("jjaeks").text).to include(group_post.content)
      expect(search_section("jjaeks").text).not_to include(personal.content)
      scope_links = Nokogiri::HTML(response.body).css("nav[aria-label='#{I18n.t('unified_search.tag_scope_label')}'] a")
      expect(scope_links.map { |link| link["href"] })
        .to include(search_path(tag: "함께", scope: "all", group_id: group.id, type: "all", per_page: 30))
      expect(scope_links.map(&:text)).to eq([ "#{group.name}에서", I18n.t("unified_search.tag_scopes.all") ])
      expect(scope_links.first["aria-current"]).to eq("page")
      expect(Nokogiri::HTML(response.body).css("nav[aria-label='#{I18n.t('unified_search.types_label')}'] a").map(&:text))
        .to eq(%w[전체 짹 책짹])

      get search_path, params: { tag: "함께", scope: "all", group_id: group.id }
      expect(search_section("jjaeks").text).to include(group_post.content, personal.content)

      get search_path, params: { q: "#다른", scope: "group", group_id: group.id,
                                 type: "jjaeks", per_page: 50, page: 3 }
      expect(response).to redirect_to(search_path(tag: "다른", scope: "group", group_id: group.id,
                                                  type: "jjaeks", per_page: 50))
      follow_redirect!
      expect(search_section("jjaeks").text).to include(next_tag_post.content)
      expect(Nokogiri::HTML(response.body).at_css("input[name='q']")["value"]).to eq("#다른")

      get search_path, params: { q: "그룹본문", scope: "group", group_id: group.id,
                                 type: "jjaeks", per_page: 50, page: 3 }
      expect(response).to redirect_to(search_path(q: "그룹본문", type: "jjaeks", per_page: 50))
      follow_redirect!
      expect(search_section("jjaeks").text).to include(group_post.content)
      expect(Nokogiri::HTML(response.body).at_css("nav[aria-label='#{I18n.t('unified_search.tag_scope_label')}']")).to be_nil
    end

    it "filters user scope without exposing another user's private posts" do
      other = User.create!(name: "다른 작성자", email: "tag-other@example.com", password: "password123!")
      own_post = writer.jjaeks.create!(content: "작성자태그 #독서")
      other_post = other.jjaeks.create!(content: "다른태그 #독서")
      private_post = writer.jjaeks.create!(content: "비공개태그 #독서", visibility: :private_jjaek)
      hidden_post = writer.jjaeks.create!(content: "숨김태그 #독서")
      hidden_post.update_columns(hidden_at: Time.current)
      deleted_post = writer.jjaeks.create!(content: "삭제태그 #독서")
      deleted_post.update_columns(deleted_at: Time.current)

      get search_path, params: { tag: "독서", scope: "user", user_id: writer.id }
      expect(search_section("jjaeks").text).to include(own_post.content)
      scope_links = Nokogiri::HTML(response.body).css("nav[aria-label='#{I18n.t('unified_search.tag_scope_label')}'] a")
      expect(scope_links.map(&:text)).to eq([ "#{writer.name}의 짹에서", I18n.t("unified_search.tag_scopes.all") ])
      [ other_post, private_post, hidden_post, deleted_post ].each do |post|
        expect(search_section("jjaeks").text).not_to include(post.content)
      end

      get search_path, params: { tag: "독서", scope: "all", user_id: writer.id }
      expect(search_section("jjaeks").text).to include(own_post.content, other_post.content)
      expect(search_section("jjaeks").text).not_to include(private_post.content)

      get search_path, params: { q: "#독서", scope: "user", user_id: writer.id, type: "jjaeks", per_page: 50 }
      expect(response).to redirect_to(search_path(tag: "독서", scope: "user", user_id: writer.id,
                                                  type: "jjaeks", per_page: 50))
    end

    it "rechecks a tagged requote's source visibility" do
      source = writer.jjaeks.create!(content: "Source")
      requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "인용글 #인용")

      get search_path, params: { tag: "인용" }
      expect(search_section("jjaeks").text).to include(requote.content)

      source.update!(visibility: :private_jjaek)
      get search_path, params: { tag: "인용" }
      expect(search_section("jjaeks").text).not_to include(requote.content)
    end

    it "rejects invalid scope combinations and inaccessible targets identically" do
      group = Group.create!(group_admin: writer, name: "숨긴 동아리", group_type: :private_group, lifecycle_status: :active)
      [ { tag: "독서", scope: "group", group_id: group.id },
        { tag: "독서", scope: "group", group_id: "999999999" },
        { tag: "독서", scope: "user", user_id: "999999999" },
        { tag: "독서", scope: "user", user_id: writer.id, group_id: group.id },
        { tag: "독서", scope: "unknown" } ].each do |search_params|
        sign_in viewer
        get search_path, params: search_params
        expect(response).to have_http_status(:not_found),
          "params=#{search_params.inspect}, redirect=#{response.location}"
      end
    end

    it "links escaped body tags from the current screen context and preserves a tag return URL" do
      group = Group.create!(group_admin: writer, name: "문맥 동아리", group_type: :public_group, lifecycle_status: :active)
      group_post = writer.jjaeks.create!(group:, content: "<script>bad</script>\n#읽기 & #READING")
      writer.jjaeks.create!(content: "프로필본문 #읽기")

      get group_path(group)
      group_page = Nokogiri::HTML(response.body)
      group_card = group_page.css("article").find { |article| article.text.include?(group_post.content) }
      expect(group_card.css("script")).to be_empty
      group_link = group_page.css("a").find { |link| link.text == "#읽기" }
      expect(Rack::Utils.parse_query(URI.parse(group_link["href"]).query))
        .to eq("tag" => "읽기", "scope" => "group", "group_id" => group.id.to_s)

      get user_path(writer)
      profile_link = Nokogiri::HTML(response.body).css("a").find { |link| link.text == "#읽기" }
      expect(Rack::Utils.parse_query(URI.parse(profile_link["href"]).query))
        .to eq("tag" => "읽기", "scope" => "user", "user_id" => writer.id.to_s)

      viewer.jjaeks.create!(content: "내프로필 #읽기")
      get user_path(viewer)
      own_link = Nokogiri::HTML(response.body).css("a").find { |link| link.text == "#읽기" }
      expect(Rack::Utils.parse_query(URI.parse(own_link["href"]).query))
        .to eq("tag" => "읽기", "scope" => "user", "user_id" => viewer.id.to_s)
      get own_link["href"]
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{search_path}'] input[name='q']")["value"]).to eq("#읽기")
      expect(Nokogiri::HTML(response.body).at_css("nav[aria-label='#{I18n.t('unified_search.tag_scope_label')}']").text)
        .to include("#{viewer.name}의 짹에서")

      get search_path, params: { tag: "읽기", scope: "group", group_id: group.id, type: "jjaeks", per_page: 50, page: 1 }
      card = search_section("jjaeks").at_css("article")
      expect(card.text).to include(group_post.content)
      expect(card.css("form")).to be_empty
      tag_link = card.css("a").find { |link| link.text == "#READING" }
      expect(Rack::Utils.parse_query(URI.parse(tag_link["href"]).query))
        .to eq("tag" => "reading", "type" => "jjaeks", "per_page" => "50",
               "scope" => "group", "group_id" => group.id.to_s)
      detail_link = card.css("a").find { |link| URI.parse(link["href"]).path == jjaek_path(group_post) }
      get detail_link["href"]
      back_link = Nokogiri::HTML(response.body).at_css("a[data-jjaek-back]")
      expect(Rack::Utils.parse_query(URI.parse(back_link["href"]).query))
        .to eq("tag" => "읽기", "scope" => "group", "group_id" => group.id.to_s,
               "type" => "jjaeks", "per_page" => "50", "page" => "1")
    end
  end
end
