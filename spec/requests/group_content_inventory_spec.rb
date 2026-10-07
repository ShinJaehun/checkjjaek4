require "rails_helper"

RSpec.describe "Group content inventory", type: :request do
  let(:group_admin) { User.create!(name: "Group admin", email: "content-inventory-admin@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Reading club", group_type: :private_group) }

  def expect_path_and_query(url, path:, query:)
    parsed = URI.parse(url)
    expect(parsed.path).to eq(path)
    expect(Rack::Utils.parse_query(parsed.query)).to eq(query.stringify_keys)
  end

  def inventory_moderation_form_action(path:, filters:)
    page = Nokogiri::HTML(response.body)
    cancel = page.css("a").find { |link| link.text.strip == I18n.t("groups.content_inventory.actions.back_from_moderation") }
    expect(cancel).to be_present
    expect_path_and_query(cancel["href"], path: content_group_path(group), query: filters)

    form = page.at_css(%(form[action^="#{path}"]))
    expect(form).to be_present
    action = form["action"]
    expect_path_and_query(action, path:, query: filters.merge(return_to: "group_content"))
    action
  end

  it "requires authentication" do
    get content_group_path(group)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders the inventory entry page for the current admin of an active group" do
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("groups.content_inventory.title"))
  end

  it "lets the current admin inspect an inactive group" do
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
  end

  it "lets the current admin inspect an operation-suspended group" do
    group.update!(operation_suspended_at: Time.current)
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
  end

  it "rejects the admin of a pending group" do
    pending = Group.create!(group_admin: group_admin, name: "Pending club", group_type: :private_group, application_purpose: "Read together")
    sign_in group_admin

    get content_group_path(pending)

    expect(response).to redirect_to(root_path)
  end

  it "rejects an ordinary member" do
    member = User.create!(name: "Member", email: "content-inventory-member@example.com", password: "password123!")
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "rejects the admin of another group" do
    other_admin = User.create!(name: "Other admin", email: "content-inventory-other-admin@example.com", password: "password123!")
    Group.create!(lifecycle_status: :active, group_admin: other_admin, name: "Other club", group_type: :public_group)
    sign_in other_admin

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "rejects a global admin who does not administer the group" do
    global_admin = User.create!(name: "Global admin", email: "content-inventory-global-only@example.com", password: "password123!", global_admin: true)
    sign_in global_admin

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "allows a global admin who is also the group's current admin" do
    global_admin = User.create!(name: "Global owner", email: "content-inventory-global-owner@example.com", password: "password123!", global_admin: true)
    owned_group = Group.create!(lifecycle_status: :active, group_admin: global_admin, name: "Owned club", group_type: :private_group)
    sign_in global_admin

    get content_group_path(owned_group)

    expect(response).to have_http_status(:ok)
  end

  it "moves inventory access to the new admin after transfer" do
    new_admin = User.create!(name: "New admin", email: "content-inventory-new-admin@example.com", password: "password123!")
    group.group_memberships.create!(user: new_admin, status: :active)
    sign_in group_admin

    get content_group_path(group)
    expect(response).to have_http_status(:ok)

    post group_admin_transfers_path(group), params: { new_admin_id: new_admin.id }
    expect(group.reload.group_admin).to eq(new_admin)

    get content_group_path(group)
    expect(response).to redirect_to(root_path)

    sign_in new_admin
    get content_group_path(group)
    expect(response).to have_http_status(:ok)
  end

  it "shows complete threads while redacting platform-hidden and deleted bodies" do
    author = User.create!(name: "Thread author", email: "group-content-thread-author@example.com", password: "password123!")
    platform_admin = User.create!(name: "Platform admin", email: "group-content-thread-platform@example.com", password: "password123!", global_admin: true)
    base_time = 2.hours.ago
    root = author.jjaeks.create!(group:, content: "VISIBLE_ROOT_BODY", created_at: base_time)
    older_comment = root.comments.create!(user: author, content: "OLDER_COMMENT_BODY", created_at: base_time + 10.minutes)
    newer_comment = root.comments.create!(user: author, content: "NEWER_COMMENT_BODY", created_at: base_time + 20.minutes)
    group_hidden_comment = root.comments.create!(user: author, content: "GROUP_HIDDEN_COMMENT_BODY")
    platform_hidden_comment = root.comments.create!(user: author, content: "PLATFORM_HIDDEN_COMMENT_BODY")
    own_comment = root.comments.create!(user: group_admin, content: "OWN_COMMENT_BODY")
    global_admin_comment = root.comments.create!(user: platform_admin, content: "GLOBAL_ADMIN_COMMENT_BODY")
    Comments::Hide.new(group_hidden_comment, actor: group_admin, public_reason: "other").call!
    Comments::Hide.new(platform_hidden_comment, actor: platform_admin, public_reason: "other").call!

    group_hidden_root = author.jjaeks.create!(group:, content: "GROUP_HIDDEN_ROOT_BODY")
    Jjaeks::Hide.new(group_hidden_root, actor: group_admin, public_reason: "other").call!
    platform_hidden_root = author.jjaeks.create!(group:, content: "PLATFORM_HIDDEN_ROOT_BODY")
    Jjaeks::Hide.new(platform_hidden_root, actor: platform_admin, public_reason: "other").call!
    deleted_root = author.jjaeks.create!(group:, content: "DELETED_ROOT_BODY")
    deleted_root.comments.create!(user: author, content: "COMMENT_ON_DELETED_ROOT")
    deleted_root.destroy_or_tombstone!
    deleted_root.update_columns(content: "DELETED_ROOT_BODY")
    own_root = group_admin.jjaeks.create!(group:, content: "OWN_ROOT_BODY")
    global_admin_root = platform_admin.jjaeks.create!(group:, content: "GLOBAL_ADMIN_ROOT_BODY")

    other_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Other club", group_type: :public_group)
    author.jjaeks.create!(group: other_group, content: "OTHER_GROUP_BODY")
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    thread = document.at_css("tbody[data-thread-id='#{root.id}']")
    row_ids = thread.css("tr").map { |row| row["id"] }
    expect(row_ids.index("group_content_comment_#{newer_comment.id}")).to be < row_ids.index("group_content_comment_#{older_comment.id}")
    expect(row_ids.last).to eq("group_content_jjaek_#{root.id}")
    expect(
      thread.at_css("#group_content_jjaek_#{root.id} [data-field='author'] img")["alt"]
    ).to eq(author.name)
    expect(document.css("thead th").last.text).to eq(I18n.t("groups.content_inventory.fields.actions"))
    root_link = document.at_css("#group_content_jjaek_#{root.id} [data-field='actions'] a")
    comment_link = document.at_css("#group_content_comment_#{newer_comment.id} [data-field='actions'] a")
    expect(root_link.text).to include(I18n.t("groups.content_inventory.actions.direct"))
    expect(root_link["href"]).to eq(jjaek_path(root))
    expect(comment_link.text).to include(I18n.t("groups.content_inventory.actions.direct"))
    expect(comment_link["href"]).to eq(jjaek_path(root, anchor: ActionView::RecordIdentifier.dom_id(newer_comment)))
    actions_for = lambda do |row_id|
      document.css("##{row_id} [data-field='actions'] a").map { |link| [ link.text.strip, link["href"] ] }
    end
    direct = I18n.t("groups.content_inventory.actions.direct")
    hide = I18n.t("jjaeks.moderation.group_admin.actions.hide")
    restore = I18n.t("jjaeks.moderation.group_admin.actions.restore")
    expect(actions_for.call("group_content_jjaek_#{root.id}")).to eq([
      [ direct, jjaek_path(root) ], [ hide, new_jjaek_group_hide_path(root, return_to: "group_content") ]
    ])
    expect(actions_for.call("group_content_jjaek_#{group_hidden_root.id}")).to eq([
      [ direct, jjaek_path(group_hidden_root) ], [ restore, new_jjaek_group_restoration_path(group_hidden_root, return_to: "group_content") ]
    ])
    expect(actions_for.call("group_content_jjaek_#{platform_hidden_root.id}")).to eq([
      [ direct, jjaek_path(platform_hidden_root) ]
    ])
    expect(actions_for.call("group_content_jjaek_#{deleted_root.id}")).to eq([
      [ direct, jjaek_path(deleted_root) ]
    ])
    comment_direct = jjaek_path(root, anchor: ActionView::RecordIdentifier.dom_id(newer_comment))
    expect(actions_for.call("group_content_comment_#{newer_comment.id}")).to eq([
      [ direct, comment_direct ],
      [ I18n.t("comments.moderation.group_admin.actions.hide"), new_jjaek_comment_group_hide_path(root, newer_comment, return_to: "group_content") ]
    ])
    expect(actions_for.call("group_content_comment_#{group_hidden_comment.id}")).to eq([
      [ direct, jjaek_path(root, anchor: ActionView::RecordIdentifier.dom_id(group_hidden_comment)) ],
      [ I18n.t("comments.moderation.group_admin.actions.restore"), new_jjaek_comment_group_restoration_path(root, group_hidden_comment, return_to: "group_content") ]
    ])
    expect(actions_for.call("group_content_comment_#{platform_hidden_comment.id}").map(&:last)).to eq([
      jjaek_path(root, anchor: ActionView::RecordIdentifier.dom_id(platform_hidden_comment))
    ])
    [ own_root, global_admin_root ].each do |unmoderatable_root|
      expect(actions_for.call("group_content_jjaek_#{unmoderatable_root.id}").map(&:last)).to eq([ jjaek_path(unmoderatable_root) ])
    end
    [ own_comment, global_admin_comment ].each do |unmoderatable_comment|
      expect(actions_for.call("group_content_comment_#{unmoderatable_comment.id}").map(&:last)).to eq([
        jjaek_path(root, anchor: ActionView::RecordIdentifier.dom_id(unmoderatable_comment))
      ])
    end
    expect(document.css("[data-field='actions'] a[href^='/admin/']")).to be_empty
    expect(response.body).to include("VISIBLE_ROOT_BODY", "OLDER_COMMENT_BODY", "GROUP_HIDDEN_ROOT_BODY", "GROUP_HIDDEN_COMMENT_BODY")
    expect(response.body).to include("COMMENT_ON_DELETED_ROOT")
    expect(response.body).not_to include("PLATFORM_HIDDEN_ROOT_BODY", "PLATFORM_HIDDEN_COMMENT_BODY", "DELETED_ROOT_BODY", "OTHER_GROUP_BODY")
    expect(document.at_css("#group_content_jjaek_#{platform_hidden_root.id} [data-field='body']").text).to include(I18n.t("groups.content_inventory.tombstones.platform_hidden"))
    expect(document.at_css("#group_content_comment_#{platform_hidden_comment.id} [data-field='body']").text).to include(I18n.t("groups.content_inventory.tombstones.platform_hidden"))
    expect(document.at_css("#group_content_jjaek_#{deleted_root.id} [data-field='body']").text).to include(I18n.t("groups.content_inventory.tombstones.deleted"))
    active_status = document.at_css("#group_content_jjaek_#{root.id} [data-field='status'] span")
    hidden_status = document.at_css("#group_content_jjaek_#{group_hidden_root.id} [data-field='status'] span")
    deleted_status = document.at_css("#group_content_jjaek_#{deleted_root.id} [data-field='status'] span")
    expect(active_status.text.strip).to eq("정상")
    expect(active_status.text).not_to include("공개")
    expect(hidden_status.text.strip).to eq("숨김")
    expect(deleted_status.text.strip).to eq("삭제됨")
    expect(document.css("a[href^='/admin/']")).to be_empty
  end

  it "returns to the filtered inventory after hiding and restoring a Jjaek" do
    author = User.create!(name: "Return author", email: "group-content-return-author@example.com", password: "password123!")
    root = author.jjaeks.create!(group:, content: "RETURN_ROOT_BODY")
    sign_in group_admin
    filters = { content: "general", content_q: "RETURN_ROOT_BODY", content_status: "active", content_sort: "oldest", all_page: "1" }

    get content_group_path(group, filters.merge(redirect_url: "https://example.invalid/elsewhere"))
    hide_link = Nokogiri::HTML(response.body).at_css("#group_content_jjaek_#{root.id} a[href*='group_hides/new']")
    expect(hide_link).to be_present
    expect_path_and_query(hide_link["href"], path: new_jjaek_group_hide_path(root), query: filters.merge(return_to: "group_content"))

    get hide_link["href"]
    hide_action = inventory_moderation_form_action(path: jjaek_group_hides_path(root), filters:)
    post hide_action, params: { moderation_action: { public_reason: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    inventory_moderation_form_action(path: jjaek_group_hides_path(root), filters:)
    expect(root.reload).not_to be_hidden

    post hide_action, params: { moderation_action: { public_reason: "other" } }
    expect(root.reload).to be_hidden
    expect_path_and_query(response.location, path: content_group_path(group), query: filters)

    filters[:content_status] = "hidden"
    get content_group_path(group, filters)
    restore_link = Nokogiri::HTML(response.body).at_css("#group_content_jjaek_#{root.id} a[href*='group_restorations/new']")
    expect(restore_link).to be_present
    expect_path_and_query(restore_link["href"], path: new_jjaek_group_restoration_path(root), query: filters.merge(return_to: "group_content"))

    get restore_link["href"]
    restore_action = inventory_moderation_form_action(path: jjaek_group_restorations_path(root), filters:)
    post restore_action, params: { moderation_action: { public_reason: "Reviewed" } }
    expect(root.reload).not_to be_hidden
    expect_path_and_query(response.location, path: content_group_path(group), query: filters)

    get new_jjaek_group_hide_path(root)
    detail_page = Nokogiri::HTML(response.body)
    expect(detail_page.at_css(%(a[href="#{jjaek_path(root)}"])).text.strip).to eq(I18n.t("jjaeks.moderation.group_admin.cancel"))
    expect(detail_page.at_css(%(form[action^="#{jjaek_group_hides_path(root)}"]))["action"]).to eq(jjaek_group_hides_path(root))
    post jjaek_group_hides_path(root), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(jjaek_path(root))
  end

  it "returns to the filtered inventory after hiding and restoring a Comment" do
    author = User.create!(name: "Comment return author", email: "group-content-comment-return@example.com", password: "password123!")
    root = author.jjaeks.create!(group:, content: "COMMENT_RETURN_PARENT")
    comment = root.comments.create!(user: author, content: "RETURN_COMMENT_BODY")
    sign_in group_admin
    filters = { content: "comments", content_q: "RETURN_COMMENT_BODY", content_status: "active", content_sort: "oldest", all_page: "1" }

    get content_group_path(group, filters)
    hide_link = Nokogiri::HTML(response.body).at_css("#group_content_comment_#{comment.id} a[href*='group_hides/new']")
    expect(hide_link).to be_present
    expect_path_and_query(hide_link["href"], path: new_jjaek_comment_group_hide_path(root, comment), query: filters.merge(return_to: "group_content"))

    get hide_link["href"]
    hide_action = inventory_moderation_form_action(path: jjaek_comment_group_hides_path(root, comment), filters:)
    post hide_action, params: { moderation_action: { public_reason: "other" } }
    expect(comment.reload).to be_hidden
    expect_path_and_query(response.location, path: content_group_path(group), query: filters)

    filters[:content_status] = "hidden"
    get content_group_path(group, filters)
    restore_link = Nokogiri::HTML(response.body).at_css("#group_content_comment_#{comment.id} a[href*='group_restorations/new']")
    expect(restore_link).to be_present
    expect_path_and_query(restore_link["href"], path: new_jjaek_comment_group_restoration_path(root, comment), query: filters.merge(return_to: "group_content"))

    get restore_link["href"]
    restore_action = inventory_moderation_form_action(path: jjaek_comment_group_restorations_path(root, comment), filters:)
    post restore_action, params: { moderation_action: { public_reason: "Reviewed" } }
    expect(comment.reload).not_to be_hidden
    expect_path_and_query(response.location, path: content_group_path(group), query: filters)
  end

  it "applies search, type, status, and activity ordering without searching author emails" do
    author = User.create!(name: "Unique Writer", email: "inventory-search-email@example.com", password: "password123!")
    book = Book.create!(title: "Filter book", authors_text: "Author")
    base_time = 3.hours.ago
    general = author.jjaeks.create!(group:, content: "SORT_SCOPE_GENERAL", created_at: base_time)
    general.comments.create!(user: author, content: "GENERAL_COMMENT", created_at: base_time + 2.hours)
    book_root = author.jjaeks.create!(group:, book:, content: "SORT_SCOPE_BOOK", created_at: base_time + 1.hour)
    hidden = author.jjaeks.create!(group:, content: "HIDDEN_FILTER_BODY")
    Jjaeks::Hide.new(hidden, actor: group_admin, public_reason: "other").call!
    deleted = author.jjaeks.create!(group:, content: "DELETED_FILTER_BODY")
    deleted.comments.create!(user: author, content: "Preserved comment")
    deleted.destroy_or_tombstone!
    sign_in group_admin

    get content_group_path(group), params: {
      content: "book", content_q: "SORT_SCOPE", content_status: "active", content_sort: "oldest"
    }
    book_document = Nokogiri::HTML(response.body)
    expect(book_document.css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ book_root.id ])
    expect(book_document.at_css("nav a[aria-current='page']").text).to include(I18n.t("groups.content_inventory.navigation.book"))
    expect(book_document.at_css("input[name='content_q']")["value"]).to eq("SORT_SCOPE")
    expect(book_document.at_css("select[name='content_status'] option[selected]")["value"]).to eq("active")
    expect(book_document.at_css("select[name='content_sort'] option[selected]")["value"]).to eq("oldest")
    expect(response.body).to include(book.title, I18n.t("groups.content_inventory.kinds.book"))

    get content_group_path(group), params: { content: "comments", content_q: "GENERAL_COMMENT" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ general.id ])
    expect(response.body).to include("SORT_SCOPE_GENERAL")

    get content_group_path(group), params: { content_status: "hidden" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ hidden.id ])

    get content_group_path(group), params: { content_status: "deleted" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ deleted.id ])

    get content_group_path(group), params: { content_q: author.email }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]")).to be_empty
    expect(response.body).to include(I18n.t("groups.content_inventory.empty"))

    get content_group_path(group), params: { content_q: "Unique Writer", content: "book" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ book_root.id ])

    get content_group_path(group), params: { content_q: "SORT_SCOPE", content_sort: "recent" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ general.id, book_root.id ])

    get content_group_path(group), params: { content_q: "SORT_SCOPE", content_sort: "oldest" }
    expect(Nokogiri::HTML(response.body).css("tbody[data-thread-id]").map { |thread| thread["data-thread-id"].to_i }).to eq([ book_root.id, general.id ])
  end

  it "preserves filters in pagination links and resets the page when the type changes" do
    author = User.create!(name: "Page author", email: "group-content-page-author@example.com", password: "password123!")
    51.times do |index|
      author.jjaeks.create!(group:, content: "PAGE_FILTER_CONTENT_#{index}")
    end
    sign_in group_admin

    get content_group_path(group), params: {
      content: "all", content_q: "PAGE_FILTER", content_status: "active", content_sort: "oldest"
    }

    document = Nokogiri::HTML(response.body)
    expect(document.css("tbody[data-thread-id]").size).to eq(50)
    next_link = document.at_css("#group_content_timeline nav a[href*='all_page=2']")
    expect(next_link).to be_present
    expect(next_link["href"]).to include("content=all", "content_q=PAGE_FILTER", "content_status=active", "content_sort=oldest")

    get content_group_path(group), params: {
      content: "all", content_q: "PAGE_FILTER", content_status: "active", content_sort: "oldest", all_page: 2
    }
    page_two = Nokogiri::HTML(response.body)
    expect(page_two.css("tbody[data-thread-id]").size).to eq(1)
    type_link = page_two.at_css("a[href*='content=general']")
    expect(type_link["href"]).to include("content_q=PAGE_FILTER", "content_status=active", "content_sort=oldest")
    expect(type_link["href"]).not_to include("all_page")
  end
end
