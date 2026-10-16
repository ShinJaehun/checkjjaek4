require "rails_helper"

RSpec.describe "Jjaek navigation", type: :request do
  let(:reader) { User.create!(name: "Reader", email: "navigation-reader@example.com", password: "password123!") }
  let(:other) { User.create!(name: "Other", email: "navigation-other@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "navigation-admin@example.com", password: "password123!", global_admin: true) }
  let(:book) { Book.create!(title: "Navigation book", authors_text: "Author") }
  let(:jjaek) { reader.jjaeks.create!(content: "RETURN_SOURCE") }
  let(:group) { Group.create!(name: "Private readers", group_admin: reader, group_type: :private_group, lifecycle_status: :active) }

  def back_link
    Nokogiri::HTML(response.body).at_css("a[data-jjaek-back]")
  end

  it "keeps home, profile, book, and club origins on the detail page" do
    sign_in reader
    origins = [ root_path, user_path(other), book_path(book), group_path(group), groups_path ]

    origins.each do |origin|
      get jjaek_path(jjaek), params: { return_to: origin }
      expect(response).to have_http_status(:ok)
      expect(back_link["href"]).to eq(origin)
    end
  end

  it "adds the home origin to existing detail and edit links" do
    jjaek
    sign_in reader
    get root_path

    card = Nokogiri::HTML(response.body).at_css("#jjaek_#{jjaek.id}")
    expect(card.at_css("a[href='#{jjaek_path(jjaek, return_to: root_path)}']")).to be_present
    expect(card.at_css("a[href='#{edit_jjaek_path(jjaek, return_to: root_path)}']")).to be_present
  end

  it "preserves the origin on edit validation failure and successful update" do
    sign_in reader
    origin = user_path(reader)
    get edit_jjaek_path(jjaek), params: { return_to: origin }
    expect(back_link["href"]).to eq(origin)
    expect(Nokogiri::HTML(response.body).at_css("input[name='return_to']")["value"]).to eq(origin)

    patch jjaek_path(jjaek), params: { return_to: origin, jjaek: { content: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(back_link["href"]).to eq(origin)
    expect(jjaek.reload.content).to eq("RETURN_SOURCE")

    patch jjaek_path(jjaek), params: { return_to: origin, jjaek: { content: "Updated" } }
    expect(response).to redirect_to(jjaek_path(jjaek, return_to: origin))
    follow_redirect!
    expect(back_link["href"]).to eq(origin)
  end

  it "does not make the updated detail page return to itself" do
    sign_in reader

    patch jjaek_path(jjaek), params: { return_to: jjaek_path(jjaek), jjaek: { content: "Updated" } }

    expect(response).to redirect_to(jjaek_path(jjaek))
    follow_redirect!
    expect(back_link["href"]).to eq(root_path)
  end

  it "preserves an original post's origin in the new requote form without changing its policy" do
    source = other.jjaeks.create!(content: "PUBLIC_SOURCE")
    sign_in reader
    get new_jjaek_path, params: { quoted_jjaek_id: source.id, return_to: user_path(other) }

    expect(response).to have_http_status(:ok)
    expect(back_link["href"]).to eq(user_path(other))
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='return_to']")["value"]).to eq(user_path(other))
    expect(page.at_css("input[name='jjaek[quoted_jjaek_id]']")["value"]).to eq(source.id.to_s)
    expect(page.at_css("input[type='submit']")["value"]).to eq(I18n.t("jjaeks.actions.publish_requote"))

    post jjaeks_path, params: { return_to: user_path(other), jjaek: { quoted_jjaek_id: source.id, content: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(back_link["href"]).to eq(user_path(other))
  end

  it "preserves the book origin after creating a book post" do
    reader.bookshelf_entries.create!(book: book)
    sign_in reader

    post jjaeks_path, params: { return_to: book_path(book), jjaek: { book_id: book.id, content: "Book post" } }

    created = reader.jjaeks.order(:id).last
    expect(response).to redirect_to(jjaek_path(created, return_to: book_path(book)))
    follow_redirect!
    expect(back_link["href"]).to eq(book_path(book))
  end

  it "falls back safely for malicious, unapproved, or inaccessible return paths" do
    sign_in other
    origins = [ "https://example.invalid", "//example.invalid", "/up", content_admin_user_path(reader), content_group_path(group), group_path(group) ]
    origins.each do |origin|
      get jjaek_path(jjaek), params: { return_to: origin }
      expect(response).to have_http_status(:ok)
      expect(back_link["href"]).to eq(root_path)
    end
  end

  it "does not use a referer as a return destination" do
    sign_in reader
    get jjaek_path(jjaek), headers: { "HTTP_REFERER" => "https://example.invalid" }
    expect(back_link["href"]).to eq(root_path)
  end

  it "preserves admin user content search, filters, sorting, and page in both directions" do
    jjaek
    sign_in admin
    filters = { content: "general", q: "RETURN_SOURCE", location: "personal", status: "active", sort: "oldest", all_page: "1" }
    origin = content_admin_user_path(reader, filters)
    get origin

    page = Nokogiri::HTML(response.body)
    direct = page.at_css("#timeline_jjaek_#{jjaek.id} [data-field='actions'] a")
    expect(direct).to be_present
    expect(Rack::Utils.parse_query(URI.parse(direct["href"]).query)["return_to"]).to eq(origin)
    get direct["href"]
    expect(back_link["href"]).to eq(origin)
  end

  it "preserves admin and club content conditions while leaving moderation links intact" do
    group.group_memberships.create!(user: other, status: :active)
    group_post = other.jjaeks.create!(group: group, content: "RETURN_GROUP")
    filters = { content: "general", content_q: "RETURN_GROUP", content_status: "active", content_sort: "oldest", all_page: "1" }

    [ [ admin, content_admin_group_path(group, filters) ], [ reader, content_group_path(group, filters) ] ].each do |actor, origin|
      sign_in actor
      get origin
      page = Nokogiri::HTML(response.body)
      direct = page.at_css("a[href^='/jjaeks/#{group_post.id}?']")
      expect(direct).to be_present
      expect(Rack::Utils.parse_query(URI.parse(direct["href"]).query)["return_to"]).to eq(origin)
      if actor == reader
        hide = page.at_css("a[href^='#{new_jjaek_group_hide_path(group_post)}?']")
        expect(Rack::Utils.parse_query(URI.parse(hide["href"]).query)["return_to"]).to eq("group_content")
      end
      get direct["href"]
      expect(back_link["href"]).to eq(origin)
    end
  end

  it "rechecks the origin's access when following the detail link" do
    sign_in reader
    get jjaek_path(jjaek), params: { return_to: content_admin_user_path(reader) }
    expect(back_link["href"]).to eq(root_path)
  end

  it "renders a single shared back link with an arrow and rejects its own detail URL" do
    sign_in reader
    get jjaek_path(jjaek), params: { return_to: jjaek_path(jjaek, return_to: discovery_path) }

    page = Nokogiri::HTML(response.body)
    expect(page.css("a[data-back-link]").size).to eq(1)
    expect(back_link["href"]).to eq(root_path)
    expect(back_link.text.strip).to eq(I18n.t("jjaeks.actions.back"))
    expect(back_link.at_css("svg[aria-hidden='true']")).to be_present
  end

  it "returns discovery's general, book, and group posts to discovery" do
    other.jjaeks.create!(content: "DISCOVERY_GENERAL")
    other.jjaeks.create!(book: book, content: "DISCOVERY_BOOK")
    public_group = Group.create!(name: "Discovery club", group_admin: other, group_type: :public_group, lifecycle_status: :active)
    other.jjaeks.create!(group: public_group, content: "DISCOVERY_GROUP")
    sign_in reader

    get discovery_path
    page = Nokogiri::HTML(response.body)
    expect(page.css("a[data-back-link]")).to be_empty
    links = page.css("a[href^='/jjaeks/']")
    expect(links.size).to eq(3)
    links.each do |link|
      expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["return_to"]).to eq(discovery_path)
      get link["href"]
      expect(response).to have_http_status(:ok)
      expect(back_link["href"]).to eq(discovery_path)
    end
  end

  it "returns post, requote, and comment notification targets to notifications" do
    profile_post = other.jjaeks.create!(target_user: reader, content: "PROFILE_NOTIFICATION")
    requote = other.jjaeks.create!(quoted_jjaek: jjaek, content: "REQUOTE_NOTIFICATION")
    comment = jjaek.comments.create!(user: other, content: "COMMENT_NOTIFICATION")
    [ [ :profile_jjaek_created, profile_post ], [ :requote_created, requote ], [ :comment_created, comment ] ].each do |action, target|
      Notification.create!(recipient: reader, actor: other, action: action, notifiable: target)
    end
    sign_in reader

    get notifications_path
    page = Nokogiri::HTML(response.body)
    expect(page.css("a[data-back-link]")).to be_empty
    links = page.css("article a[href^='/jjaeks/']")
    expect(links.size).to eq(3)
    links.each do |link|
      get link["href"]
      expect(response).to have_http_status(:ok)
      expect(back_link["href"]).to eq(notifications_path)
    end
  end

  [ :platform, :group ].each do |authority|
    it "preserves the #{authority} investigation origin after moderation failure, cancel, hide, and restore" do
      group.group_memberships.create!(user: other, status: :active)
      target = other.jjaeks.create!(group: group, content: "MODERATION_RETURN")
      filters = { content: "general", content_q: "MODERATION_RETURN", content_status: "active", content_sort: "oldest", all_page: "2" }
      origin = authority == :platform ? content_admin_group_path(group, filters.merge(q: "Readers", page: "3")) : content_group_path(group, filters)
      sign_in(authority == :platform ? admin : reader)

      get jjaek_path(target, return_to: origin)
      link = Nokogiri::HTML(response.body).at_css("a[data-jjaek-moderation-action]")
      get link["href"]
      page = Nokogiri::HTML(response.body)
      detail = jjaek_path(target, return_to: origin)
      expect(page.at_css("a[data-back-link]")["href"]).to eq(detail)
      cancel = page.css("a").find { |item| item.text.strip == I18n.t(authority == :platform ? "admin.jjaeks.moderation.cancel" : "jjaeks.moderation.group_admin.cancel") }
      expect(cancel["href"]).to eq(detail)
      action = page.at_css("form[action*='hides']")["action"]

      post action, params: { moderation_action: { public_reason: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(detail)
      expect(target.reload).not_to be_hidden
      post action, params: { moderation_action: { public_reason: "other" } }
      expect(response).to redirect_to(detail)
      expect(target.reload).to be_hidden
      follow_redirect!
      expect(back_link["href"]).to eq(origin)

      get Nokogiri::HTML(response.body).at_css("a[data-jjaek-moderation-action]")["href"]
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("a[data-back-link]")["href"]).to eq(detail)
      post page.at_css("form[action*='restorations']")["action"], params: { moderation_action: { public_reason: "Reviewed" } }
      expect(response).to redirect_to(detail)
      expect(target.reload).not_to be_hidden
      follow_redirect!
      expect(back_link["href"]).to eq(origin)
    end
  end

  it "retains the investigation origin and comment anchor after platform comment moderation" do
    comment = jjaek.comments.create!(user: other, content: "COMMENT_MODERATION")
    origin = content_admin_user_path(reader, content: "comments", q: "COMMENT", all_page: "2")
    sign_in admin
    get jjaek_path(jjaek, return_to: origin)
    page = Nokogiri::HTML(response.body)
    get page.at_css("#comment_#{comment.id} a[href*='hides/new']")["href"]
    page = Nokogiri::HTML(response.body)
    detail = jjaek_path(jjaek, return_to: origin, anchor: "comment_#{comment.id}")
    expect(page.at_css("a[data-back-link]")["href"]).to eq(detail)
    post page.at_css("form[action*='hides']")["action"], params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(detail)
    expect(comment.reload).to be_hidden
    follow_redirect!
    expect(back_link["href"]).to eq(origin)
  end

  it "passes the detail origin to delete and redirects to that accessible list" do
    sign_in reader
    get jjaek_path(jjaek, return_to: discovery_path)
    form = Nokogiri::HTML(response.body).at_css("form[action*='/jjaeks/#{jjaek.id}']")
    expect(Rack::Utils.parse_query(URI.parse(form["action"]).query)["return_to"]).to eq(discovery_path)
    delete form["action"]
    expect(response).to redirect_to(discovery_path)
    expect(Jjaek.exists?(jjaek.id)).to be(false)
  end

  it "does not return to a deleted detail even when deletion leaves a group tombstone" do
    sign_in reader
    target = reader.jjaeks.create!(group: group, content: "DELETE_GROUP")
    target.comments.create!(user: reader, content: "Preserved discussion")
    delete jjaek_path(target, return_to: jjaek_path(target))
    expect(response).to redirect_to(group_path(group))
    expect(target.reload).to be_deleted
  end

  it "rejects external and unauthorized origins after deletion" do
    sign_in reader
    [ "https://example.invalid", content_admin_user_path(other) ].each do |origin|
      target = reader.jjaeks.create!(content: "DELETE_WITH_UNSAFE_ORIGIN")
      delete jjaek_path(target, return_to: origin)
      expect(response).to redirect_to(root_path)
    end
  end

  it "keeps discovery and notification origins through edit and create validation failures" do
    reader.bookshelf_entries.create!(book: book)
    sign_in reader
    [ discovery_path, notifications_path ].each do |origin|
      patch jjaek_path(jjaek), params: { return_to: origin, jjaek: { content: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(back_link["href"]).to eq(origin)
      post jjaeks_path, params: { return_to: origin, jjaek: { book_id: book.id, content: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Nokogiri::HTML(response.body).at_css("input[name='return_to']")["value"]).to eq(origin)
      post jjaeks_path, params: { return_to: origin, jjaek: { book_id: book.id, content: "New book post" } }
      created = reader.jjaeks.order(:id).last
      expect(response).to redirect_to(jjaek_path(created, return_to: origin))
    end
  end

  it "provides a source link on the independent requote list and returns its detail links to the list" do
    requote = other.jjaeks.create!(quoted_jjaek: jjaek, content: "LIST_REQUOTE")
    sign_in reader
    get jjaek_requotes_path(jjaek)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[data-back-link]")["href"]).to eq(jjaek_path(jjaek))
    detail = page.at_css("#jjaek_#{requote.id} a[href^='/jjaeks/#{requote.id}?']")
    get detail["href"]
    expect(back_link["href"]).to eq(jjaek_requotes_path(jjaek))
  end
end
