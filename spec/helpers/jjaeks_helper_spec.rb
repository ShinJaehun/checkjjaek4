require "rails_helper"

RSpec.describe JjaeksHelper, type: :helper do
  it "uses distinct decorative SVG icons for posting locations and visibility choices" do
    paths = %w[personal group public_jjaek book_friends private_jjaek].map do |key|
      icon = Nokogiri::HTML.fragment(helper.jjaek_option_icon(key)).at_css("svg")
      expect(icon["aria-hidden"]).to eq("true")
      icon.at_css("path")["d"]
    end
    expect(paths.uniq.size).to eq(5)
  end

  let(:viewer) { User.create!(name: "Reader", email: "context-helper@example.com", password: "password123!") }
  let(:author) { User.create!(name: "Author", email: "context-helper-author@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Readers", group_admin: author, group_type: :private_group, lifecycle_status: :active) }

  before do
    helper.extend UsersHelper
    actor = viewer
    helper.define_singleton_method(:policy) { |record| Pundit.policy!(actor, record) }
  end

  it "names the other participant in each viewer's language and keeps observer wording neutral" do
    post = author.jjaeks.new(target_user: viewer, content: "Private conversation")
    { ko: [ "Reader님과 나만 보기", "Author님과 나만 보기", "당사자만 보기" ],
      en: [ "Only Reader and me", "Only Author and me", "Participants only" ] }.each do |locale, labels|
      I18n.with_locale(locale) do
        [ author, viewer, nil ].zip(labels).each do |actor, label|
          allow(helper).to receive(:current_user).and_return(actor)
          expect(helper.jjaek_visibility_label(post)).to eq(label)
        end
      end
    end
  end

  it "reuses an empty prepared sharing result without falling back to policy" do
    post = author.jjaeks.create!(content: "Public post")
    helper.instance_variable_set(:@group_share_destinations_by_jjaek_id, { post.id => [] })
    expect(helper).not_to receive(:policy)

    expect(helper.show_group_share_action?(post)).to be(false)
  end

  it "uses the sharing policy when the record has no prepared result" do
    group.group_memberships.create!(user: viewer, status: :active)
    post = author.jjaeks.create!(content: "Public post")
    helper.instance_variable_set(:@group_share_destinations_by_jjaek_id, {})

    expect(helper.show_group_share_action?(post)).to be(true)
  end

  describe "card summaries" do
    let(:post) { author.jjaeks.create!(content: "Summary post") }

    before do
      allow(helper).to receive(:current_user).and_return(viewer)
    end

    it "uses prepared zero counts and a missing own like without querying associations" do
      helper.instance_variable_set(:@jjaek_comment_counts, { post.id => 0 })
      helper.instance_variable_set(:@jjaek_like_counts, { post.id => 0 })
      helper.instance_variable_set(:@current_user_likes_by_jjaek_id, { post.id => nil })
      expect(post).not_to receive(:comments_count)
      expect(post).not_to receive(:likes_count)
      expect(post).not_to receive(:likes)

      expect(helper.jjaek_comments_count(post)).to eq(0)
      expect(helper.jjaek_likes_count(post)).to eq(0)
      expect(helper.current_user_like_for(post)).to be_nil
    end

    it "uses prepared counts and attaches the own like to the displayed parent" do
      like = post.likes.create!(user: viewer)
      helper.instance_variable_set(:@jjaek_comment_counts, { post.id => 3 })
      helper.instance_variable_set(:@jjaek_like_counts, { post.id => 2 })
      helper.instance_variable_set(:@current_user_likes_by_jjaek_id, { post.id => like })
      displayed_post = Jjaek.find(post.id)

      expect(helper.jjaek_comments_count(displayed_post)).to eq(3)
      expect(helper.jjaek_likes_count(displayed_post)).to eq(2)
      expect(helper.current_user_like_for(displayed_post)).to eq(like)
      expect(like.jjaek).to equal(displayed_post)
    end

    it "finds only the own like in an unprepared context without loading the association" do
      post.likes.create!(user: author)
      own_like = post.likes.create!(user: viewer)

      expect(helper.current_user_like_for(post)).to eq(own_like)
      expect(post.association(:likes)).not_to be_loaded
      expect(helper.jjaek_likes_count(post)).to eq(2)
    end

    it "keeps persisted-only fallbacks for loaded associations with form objects" do
      post.comments.create!(user: author, content: "Saved comment")
      post.likes.create!(user: author)
      post.comments.load
      post.likes.load
      post.comments.build(user: viewer, content: "Draft")
      post.likes.build(user: viewer)

      expect(helper.jjaek_comments_count(post)).to eq(1)
      expect(helper.jjaek_likes_count(post)).to eq(1)
      expect(helper.current_user_like_for(post)).to be_nil
    end
  end

  it "uses a neutral Club space badge without a book title or content-type label in the header" do
    book = Book.create!(title: "Header book")
    [ nil, book ].each do |attachment|
      post = create_jjaek_with_books(legacy_source_kind: "book", books: [ attachment ], user: author, group:, content: "Group post")
      label = Nokogiri::HTML.fragment(helper.jjaek_context_label(post))
      expect(label.text).to eq("Author님이 동아리 Readers에 남긴 짹")
      expect(label.at_css("a[href='#{group_path(group)}']").text).to eq(group.name)
      badge = label.at_css("span")
      expect(badge.text).to eq(I18n.t("jjaeks.contexts.group_badge"))
      expect(badge["class"]).to include("bg-stone-50", "font-normal", "text-[10px]")
      expect(badge.next_element["href"]).to eq(group_path(group))
    end
  end

  it "links the recipient's 20px avatar and name in the original sentence" do
    post = author.jjaeks.create!(target_user: viewer, content: "For Reader")
    label = Nokogiri::HTML.fragment(helper.jjaek_context_label(post))
    link = label.at_css("a[href='#{user_path(viewer)}']")

    expect(label.text).to eq("Author님이 Reader님에게 남긴 짹")
    expect(link.at_css("img")["src"]).to include("user_profile_")
    expect(link.at_css("img")["class"]).to include("h-5", "w-5")
    expect(link.at_css("img").next_element.text).to eq(viewer.name)
  end

  %i[personal group_quote group_share].each do |context|
    %i[general book].each do |kind|
      it "links the original author's thumbnail and name for a #{context} #{kind} requote" do
        group.group_memberships.create!(user: viewer, status: :active) unless context == :personal
        book = Book.create!(title: "Quoted book", authors_text: "Author") if kind == :book
        source = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: author, group: context == :group_quote ? group : nil, content: "Source")
        requote = viewer.jjaeks.create!(quoted_jjaek: source, group: context == :personal ? nil : group, content: "Requote")

        label = Nokogiri::HTML.fragment(helper.jjaek_context_label(requote))
        expect(label.text).to include("Author님의 짹")
        expect(label.text).not_to include("책짹", "추천짹")
        if context != :personal
          expect(label.at_css("span.inline-block").text).to eq(I18n.t("jjaeks.contexts.group_badge"))
          expect(label.at_css("a[href='#{group_path(group)}']").text).to eq(group.name)
        end
        link = label.at_css("a[href='#{user_path(author)}']")
        image = link.at_css("img")
        expect(image["class"]).to include("h-5", "w-5", "rounded-full", "object-cover")
        expect(image["alt"]).to eq(author.name)
        expect(image.next_element.text).to eq(author.name)
        expect(link["class"]).to include("inline-flex", "gap-1", "align-middle")
        expect(label.at_css("a[href='#{user_path(viewer)}'] img")).to be_nil
      end
    end
  end

  it "uses the same personal header for ordinary, legacy book and recommendation posts" do
    book = Book.create!(title: "Header book")
    ordinary = author.jjaeks.create!(content: "Ordinary post")
    book_post = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: author, content: "Book post")
    recommendation = build_jjaek_with_books(legacy_source_kind: "recommendation", user: author, content: "Recommendation")
    recommendation.jjaek_book_attachments.build(book:, position: 0)
    recommendation.save!
    [ ordinary, book_post, recommendation ].each do |post|
      label = Nokogiri::HTML.fragment(helper.jjaek_context_label(post))
      expect(label.text).to eq("Author님의 짹")
      expect(label.at_css("a[href='#{user_path(author)}']").text).to eq(author.name)
      expect(label.css("img")).to be_empty
    end
  end

  it "does not expose the original author's thumbnail after source deletion" do
    source = author.jjaeks.create!(content: "Source")
    requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "Requote")
    source.destroy!

    label = Nokogiri::HTML.fragment(helper.jjaek_context_label(requote.reload))

    expect(label.css("img")).to be_empty
    expect(label.at_css("a[href='#{user_path(author)}']")).to be_nil
  end

  it "does not expose the original author's thumbnail when the source is no longer readable" do
    source = author.jjaeks.create!(content: "Source")
    requote = viewer.jjaeks.create!(quoted_jjaek: source, content: "Requote")
    source.update!(visibility: :private_jjaek)

    label = Nokogiri::HTML.fragment(helper.jjaek_context_label(requote.reload))

    expect(label.css("img")).to be_empty
    expect(label.at_css("a[href='#{user_path(author)}']")).to be_nil
  end

  it "accepts accessible internal origins and preserves allowed management filters" do
    admin = User.create!(name: "Admin", email: "context-helper-admin@example.com", password: "password123!", global_admin: true)
    helper.define_singleton_method(:policy) { |record| Pundit.policy!(admin, record) }
    author.update!(handle: "context_author")
    filters = { content: "comments", q: "a & b", location: "personal", status: "hidden", sort: "oldest", all_page: "3", per_page: "100",
                inventory: { q: "Author", status: "active", role: "regular", sort: "name", page: "2", per_page: "50" } }
    origin = content_admin_user_path(author, filters)

    expect(helper.validated_jjaek_return_path(origin)).to eq(origin)
    expect(helper.validated_jjaek_return_path(root_path)).to eq(root_path)
    expect(helper.validated_jjaek_return_path(user_path(author))).to eq(user_path(author))
  end

  it "resolves handle and old numeric return paths after a user sets their handle" do
    profile_path = user_path(viewer)
    library_path = user_library_path(viewer, sort: "title")
    viewer.update!(handle: "context_reader")

    [ profile_path, user_path(viewer) ].each do |path|
      expect(helper.validated_jjaek_return_path(path)).to eq(user_path(viewer))
    end
    [ library_path, user_library_path(viewer, sort: "title") ].each do |path|
      expect(helper.validated_jjaek_return_path(path)).to eq(user_library_path(viewer, sort: "title"))
    end
    search_path = book_search_path(query: "book", search_origin: profile_path)
    expect(helper.validated_jjaek_return_path(search_path)).to eq(book_search_path(query: "book", search_origin: user_path(viewer)))
  end

  it "preserves separate group inventory and content pagination while dropping unapproved return parameters" do
    admin = User.create!(name: "Admin", email: "context-group-admin@example.com", password: "password123!", global_admin: true)
    helper.define_singleton_method(:policy) { |record| Pundit.policy!(admin, record) }
    filters = { content: "general", content_q: "thread", content_status: "active", content_sort: "oldest", all_page: "2", per_page: "100",
                inventory: { q: "Readers", group_type: "private_group", status: "active", operation_status: "normal", sort: "name", page: "3", per_page: "50" } }
    origin = content_admin_group_path(group, filters)

    expect(helper.validated_jjaek_return_path(origin)).to eq(origin)
    candidate = content_admin_group_path(group, filters.merge(return_to: "https://example.com",
      inventory: filters[:inventory].merge(return_to: "//example.com", redirect_url: "https://example.com")))
    expect(helper.validated_jjaek_return_path(candidate)).to eq(origin)

    actor = viewer
    helper.define_singleton_method(:policy) { |record| Pundit.policy!(actor, record) }
    expect(helper.validated_jjaek_return_path(origin)).to be_nil
  end

  it "rejects external, unapproved, missing, and inaccessible paths" do
    candidates = [ "https://example.com", "//example.com", "/\\example.com", "/up", "/users/sign_out", "/users/999999999", group_path(group), content_admin_user_path(author), content_group_path(group), [ root_path ] ]

    candidates.each do |candidate|
      expect(helper.validated_jjaek_return_path(candidate)).to be_nil
    end
  end

  it "ignores submit metadata without widening the allowed return filters" do
    allow(ActionController::Parameters).to receive(:action_on_unpermitted_parameters).and_return(:raise)
    filters = { q: "a & b", type: "jjaeks", per_page: "50", page: "2" }

    expect(helper.validated_jjaek_return_path(search_path(filters.merge(commit: "검색"))))
      .to eq(search_path(filters))
    expect(helper.validated_jjaek_return_path(search_path(filters.merge(
      return_to: user_path(author), redirect_url: "https://example.com", modal: "1"
    )))).to eq(search_path(filters))
  end

  it "drops unknown query keys and nested return parameters" do
    expect(helper.validated_jjaek_return_path(user_path(author, return_to: "https://example.com", redirect_url: "https://example.com"))).to eq(user_path(author))
  end

  it "preserves a separately validated search origin together with search filters" do
    search_path = book_search_path(query: "a & b", page: 2, search_origin: user_path(author))
    expect(helper.validated_jjaek_return_path(search_path)).to eq(search_path)

    candidate = book_search_path(query: "a & b", page: 2,
                                search_origin: user_path(author, return_to: "https://example.com"),
                                return_to: "https://example.com", modal: "1")
    expect(helper.validated_jjaek_return_path(candidate)).to eq(search_path)
  end

  it "drops invalid search origins and rechecks their access" do
    origins = [ "https://example.com", "//example.com", "/\\example.com", "/users/sign_out", "/users/999999999", group_path(group), [ root_path ] ]
    origins.each do |origin|
      candidate = book_search_path(query: "book", page: 2, search_origin: origin)
      expect(helper.validated_jjaek_return_path(candidate)).to eq(book_search_path(query: "book", page: 2))
    end

    membership = group.group_memberships.create!(user: viewer, status: :active)
    candidate = book_search_path(query: "book", search_origin: group_path(group))
    expect(helper.validated_jjaek_return_path(candidate)).to eq(candidate)
    membership.destroy!
    expect(helper.validated_jjaek_return_path(candidate)).to eq(book_search_path(query: "book"))
    expect(helper.validated_jjaek_return_path(book_search_path(group_id: group.id))).to be_nil
  end

  it "keeps search origins to one level without forwarding nested navigation" do
    origin = book_search_path(query: "previous", search_origin: root_path, return_to: user_path(author))
    candidate = book_search_path(query: "current", search_origin: origin)
    expect(helper.validated_jjaek_return_path(candidate)).to eq(
      book_search_path(query: "current", search_origin: book_search_path(query: "previous"))
    )
  end

  it "checks access to a group-specific book origin" do
    book = Book.create!(title: "Context book", authors_text: "Author")
    expect(helper.validated_jjaek_return_path(book_path(book, group_id: group.id))).to be_nil
    group.group_memberships.create!(user: viewer, status: :active)
    expect(helper.validated_jjaek_return_path(book_path(book, group_id: group.id))).to eq(book_path(book, group_id: group.id))
  end
end
