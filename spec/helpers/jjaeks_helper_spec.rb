require "rails_helper"

RSpec.describe JjaeksHelper, type: :helper do
  it "uses distinct decorative SVG icons for posting locations and visibility choices" do
    paths = %w[personal group public_jjaek book_friends private_jjaek].map do |key|
      icon = Nokogiri::HTML.fragment(helper.book_posting_icon(key)).at_css("svg")
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

  it "adds a neutral inline club badge before the existing group name link" do
    post = author.jjaeks.create!(group: group, content: "Group post")
    label = Nokogiri::HTML.fragment(helper.jjaek_context_label(post))

    badge = label.at_css("span")
    expect(badge.text).to eq(I18n.t("jjaeks.contexts.group_badge"))
    expect(badge.next_element.name).to eq("a")
    expect(badge.next_element["href"]).to eq(group_path(group))
    expect(label.text).to include("Author님이 동아리 Readers에 남긴 짹")
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
        source = author.jjaeks.create!(book: book, group: context == :group_quote ? group : nil, content: "Source")
        requote = viewer.jjaeks.create!(quoted_jjaek: source, group: context == :personal ? nil : group, content: "Requote")

        label = Nokogiri::HTML.fragment(helper.jjaek_context_label(requote))
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

  it "does not add an inline thumbnail to an ordinary author's name" do
    post = author.jjaeks.create!(content: "Ordinary post")
    label = Nokogiri::HTML.fragment(helper.jjaek_context_label(post))

    expect(label.at_css("a[href='#{user_path(author)}']").text).to eq(author.name)
    expect(label.css("img")).to be_empty
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
    filters = { content: "comments", q: "a & b", location: "personal", status: "hidden", sort: "oldest", all_page: "3" }
    origin = content_admin_user_path(author, filters)

    expect(helper.validated_jjaek_return_path(origin)).to eq(origin)
    expect(helper.validated_jjaek_return_path(root_path)).to eq(root_path)
    expect(helper.validated_jjaek_return_path(user_path(author))).to eq(user_path(author))
  end

  it "rejects external, unapproved, missing, and inaccessible paths" do
    candidates = [ "https://example.com", "//example.com", "/\\example.com", "/up", "/users/sign_out", "/users/999999999", group_path(group), content_admin_user_path(author), content_group_path(group), [ root_path ] ]

    candidates.each do |candidate|
      expect(helper.validated_jjaek_return_path(candidate)).to be_nil
    end
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
    origins = ["https://example.com", "//example.com", "/\\example.com", "/users/sign_out", "/users/999999999", group_path(group), [root_path]]
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
