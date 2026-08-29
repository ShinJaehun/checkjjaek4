require "rails_helper"

RSpec.describe "Admin group approvals", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "admin-group-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:group) { Group.create!(group_admin: group_admin, name: "Pending club", group_type: :public_group, application_purpose: "Create a reading circle") }
  let!(:admin) { User.create!(name: "Admin", email: "group-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true) }
  let!(:opening_event) { group.lifecycle_events.create!(actor: group_admin, event_type: :opening_requested, detail: group.application_purpose) }

  def listed_group_ids
    Nokogiri::HTML(response.body).css("tbody tr").filter_map { |row| row["id"]&.delete_prefix("group_")&.to_i }
  end

  it "requires authentication for the inventory" do
    get admin_groups_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "blocks a non-admin from the approval list and approve action" do
    sign_in group_admin

    get admin_groups_path
    expect(response).to redirect_to(root_path)

    get admin_group_path(group)
    expect(response).to redirect_to(root_path)

    patch approve_admin_group_path(group)
    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_pending_approval
  end

  it "lets a global admin list and approve pending groups" do
    sign_in admin

    get admin_groups_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name, group_admin.name, "개설 신청", "운영 승인", "운영 정보 보기")
    expect(response.body).not_to include("운영 이력", "Create a reading circle")
    expect(response.body).not_to include("신청 정보 갱신")

    get admin_group_path(group)
    opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
    expect(response.body).to include("승인 대기", "운영 이력")
    expect(response.body).to include("콘텐츠")
    expect(opening_card.text).to include("개설 목적", "Create a reading circle", "신청", I18n.l(opening_event.created_at, format: :short))
    expect(opening_card.text).not_to include("승인")

    patch approve_admin_group_path(group)
    expect(group.reload).to be_active
    approval = group.lifecycle_events.opening_approved.sole
    expect(approval.actor).to eq(admin)
    expect(approval.created_at).to be_present

    get admin_group_path(group)
    expect(response.body.scan("동아리 개설").size).to eq(1)
    opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
    expect(opening_card.text).to include("신청", "승인", I18n.l(approval.created_at, format: :short))
  end

  it "shows a reactivation request with previous closure details" do
    legacy_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Returning club", group_type: :public_group)
    closed_at = Time.current
    legacy_group.update!(lifecycle_status: :inactive, closure_reason: "The first season ended", closed_at: closed_at)
    legacy_group.update!(lifecycle_status: :pending_approval)
    legacy_group.lifecycle_events.create!(actor: group_admin, event_type: :operations_closed, detail: "The first season ended", created_at: closed_at)
    legacy_group.lifecycle_events.create!(actor: group_admin, event_type: :reactivation_requested)
    sign_in admin

    get admin_groups_path

    expect(response.body).to include("재활성화 요청", "운영 정보 보기", "운영 승인")
    expect(response.body).not_to include("운영 이력", "The first season ended")

    get admin_group_path(legacy_group)
    expect(response.body).to include("승인 대기", "동아리 운영 종료", "동아리 재운영", "The first season ended", I18n.l(closed_at, format: :short), "운영 이력")
    reactivation_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 재운영") }
    expect(reactivation_card.text).to include("신청")
    expect(reactivation_card.text).not_to include("승인")

    patch approve_admin_group_path(legacy_group)
    expect(legacy_group.reload).to be_active
    reapproval = legacy_group.lifecycle_events.reactivation_approved.sole
    expect(reapproval.actor).to eq(admin)

    get admin_group_path(legacy_group)
    expect(response.body.scan("동아리 재운영").size).to eq(1)
    reactivation_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 재운영") }
    expect(reactivation_card.text).to include("신청", "승인", I18n.l(reapproval.created_at, format: :short))
  end

  it "falls back to the current purpose on admin details for a legacy pending group without events" do
    legacy_group = Group.create!(group_admin: group_admin, name: "Legacy application", group_type: :public_group, application_purpose: "Legacy purpose")
    sign_in admin

    get admin_group_path(legacy_group)

    expect(response.body).to include("Legacy purpose", "기록된 운영 이력이 없습니다.")
  end

  it "shows an approval-only opening stage for a legacy pending group" do
    legacy_group = Group.create!(group_admin: group_admin, name: "Legacy approval", group_type: :public_group, application_purpose: "Legacy purpose")
    sign_in admin

    patch approve_admin_group_path(legacy_group)
    approval = legacy_group.lifecycle_events.opening_approved.sole
    get admin_group_path(legacy_group)

    expect(response.body).to include("동아리 개설", "신청", "기록 없음", "승인", I18n.l(approval.created_at, format: :short))
  end

  it "shows read-only operations details for every group" do
    active_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Active club", group_type: :private_group)
    sign_in admin

    get admin_groups_path
    expect(response.body).to include(active_group.name, "운영 정보 보기")

    get admin_group_path(group)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name, group.application_purpose, "운영 이력")
    expect(response.body).not_to include("동아리 운영 종료", "재활성화 요청", "수정하기")
  end

  it "searches by group or group admin and combines type and lifecycle filters" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Hidden Reading Club", group_type: :private_group)
    sign_in admin

    get admin_groups_path, params: { q: group_admin.email, group_type: "private_group", status: "active" }
    expect(listed_group_ids).to eq([ private_group.id ])
    expect(Nokogiri::HTML(response.body).at_css("#group_#{private_group.id}").text).to include("비공개", "운영")

    get admin_groups_path, params: { q: "Pending club", status: "pending_approval" }
    expect(listed_group_ids).to eq([ group.id ])
  end

  it "applies whitelisted sorts and ignores invalid values" do
    older = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Aged club", group_type: :approval_group, created_at: 5.days.ago)
    sign_in admin

    get admin_groups_path, params: { sort: "name" }
    expect(listed_group_ids.first).to eq(older.id)
    get admin_groups_path, params: { sort: "oldest" }
    expect(listed_group_ids.first).to eq(older.id)
    get admin_groups_path, params: { sort: "recent" }
    expect(listed_group_ids.first).to eq(group.id)
    get admin_groups_path, params: { sort: "updated" }
    expect(listed_group_ids.first).to eq(group.id)
    get admin_groups_path, params: { sort: "invalid", group_type: "invalid", from: "ignored", to: "ignored", page: "invalid" }
    expect(response).to have_http_status(:ok)
  end

  it "paginates the unified inventory and preserves query parameters" do
    50.times { |index| Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Paged club #{index}", group_type: :public_group) }
    sign_in admin

    get admin_groups_path, params: { q: "club", page: 2 }
    expect(listed_group_ids.size).to eq(1)
    expect(response.body).to include("q=club", "page=1")
  end

  it "shows private metadata to global admins without changing ordinary private access" do
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private metadata", group_type: :private_group)
    ordinary_user = User.create!(name: "Ordinary", email: "ordinary-private@example.com", password: "password123!")

    sign_in admin
    get admin_groups_path, params: { q: "Private metadata" }
    expect(listed_group_ids).to eq([ private_group.id ])

    get admin_group_path(private_group)
    expect(response.body).to include(group_members_path(private_group), "회원 관리")

    sign_in ordinary_user
    get group_path(private_group)
    expect(response).to have_http_status(:not_found)
  end

  it "does not grant group_admin lifecycle actions through global admin status" do
    active_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Group admin only", group_type: :public_group)
    inactive_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Closed group_admin only", group_type: :public_group)
    inactive_group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
    sign_in admin

    get edit_group_path(active_group)
    expect(response).to redirect_to(root_path)
    patch group_path(active_group), params: { group: { name: "Admin edit" } }
    expect(response).to redirect_to(root_path)
    patch close_group_path(active_group), params: { group: { closure_reason: "Admin close" } }
    expect(response).to redirect_to(root_path)
    patch request_reactivation_group_path(inactive_group)
    expect(response).to redirect_to(root_path)

    expect(active_group.reload.name).to eq("Group admin only")
    expect(active_group).to be_active
    expect(inactive_group.reload).to be_inactive
  end

  it "shows only the Group's Jjaeks and comments with authors and direct links" do
    active_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Content group", group_type: :private_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Other content group", group_type: :public_group)
    member = User.create!(name: "Content member", email: "group-content-member@example.com", password: "password123!")
    book = Book.create!(title: "Group content book", authors_text: "Author")
    general = group_admin.jjaeks.create!(group: active_group, content: "GROUP_GENERAL_CONTENT")
    book_jjaek = member.jjaeks.create!(group: active_group, book:, content: "GROUP_BOOK_CONTENT")
    comment = general.comments.create!(user: member, content: "GROUP_COMMENT_CONTENT")
    deleted = member.jjaeks.create!(group: active_group, content: "GROUP_DELETED_CONTENT")
    deleted_comment = deleted.comments.create!(user: group_admin, content: "COMMENT_ON_DELETED_GROUP_CONTENT")
    deleted.destroy_or_tombstone!
    other_jjaek = group_admin.jjaeks.create!(group: other_group, content: "OTHER_GROUP_CONTENT")
    sign_in admin

    get admin_group_path(active_group)

    document = Nokogiri::HTML(response.body)
    timeline = document.at_css("#admin_group_content_timeline")
    expect(timeline.css("th").map { |header| header.text.strip }).to eq(
      [ "종류", "작성자", "본문", "참고", "상태", "작성 시각", "작업" ]
    )

    general_row = timeline.at_css("#group_timeline_jjaek_#{general.id}")
    book_row = timeline.at_css("#group_timeline_jjaek_#{book_jjaek.id}")
    comment_row = timeline.at_css("#group_timeline_comment_#{comment.id}")
    deleted_row = timeline.at_css("#group_timeline_jjaek_#{deleted.id}")
    deleted_comment_row = timeline.at_css("#group_timeline_comment_#{deleted_comment.id}")
    expect(general_row.at_css("[data-field='reference']").text.strip).to eq("-")
    expect(general_row.at_css("a[href='#{admin_user_path(group_admin)}']")).to be_present
    expect(book_row.at_css("[data-field='reference']").text).to include("책", book.title)
    expect(book_row.at_css("a[href='#{book_path(book)}']")).to be_present
    expect(book_row.at_css("a[href='#{admin_user_path(member)}']")).to be_present
    expect(comment_row.at_css("[data-field='reference']").text).to include("원문", group_admin.name, general.content)
    expect(comment_row.at_css("a[href='#{admin_user_path(member)}']")).to be_present
    expect(deleted_row.at_css("[data-field='body']").text.strip).to eq("-")
    expect(deleted_row.at_css("[data-field='status']").text.strip).to eq("삭제")
    expect(deleted_comment_row.at_css("[data-field='reference']").text).to include(member.name, "-")
    expect(timeline.text).not_to include(other_jjaek.content)
    expect(book_row.at_css("a[href='#{jjaek_path(book_jjaek)}']")).to be_present
    comment_anchor = ActionView::RecordIdentifier.dom_id(comment)
    expect(comment_row.at_css("a[href='#{jjaek_path(general, anchor: comment_anchor)}']")).to be_present

    navigation = document.at_css("nav[aria-label='동아리 콘텐츠 종류']")
    expect(navigation.css("a").map { |link| link.text.strip }).to eq([ "전체", "짹", "책짹", "댓글" ])
    expect(navigation.at_css("a[aria-current='page']").text.strip).to eq("전체")
    expect(navigation.text).not_to include("다시짹")

    lifecycle_position = response.body.index("운영 이력")
    back_position = response.body.index("동아리 운영 관리로")
    content_position = response.body.index("id=\"admin_group_content\"")
    expect(content_position).to be > lifecycle_position
    expect(content_position).to be > back_position
  end

  it "filters Group content and preserves filters across navigation" do
    active_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Filtered content group", group_type: :public_group)
    member = User.create!(name: "Filter member", email: "filter-member@example.com", password: "password123!")
    book = Book.create!(title: "Filtered content book", authors_text: "Author")
    general = group_admin.jjaeks.create!(group: active_group, content: "FILTER_GROUP_GENERAL")
    book_jjaek = member.jjaeks.create!(group: active_group, book:, content: "FILTER_GROUP_BOOK")
    comment = general.comments.create!(user: member, content: "FILTER_GROUP_COMMENT")
    deleted = member.jjaeks.create!(group: active_group, content: "FILTER_GROUP_DELETED")
    preservation_comment = deleted.comments.create!(user: group_admin, content: "PRESERVE_FILTER_GROUP_DELETED")
    deleted.destroy_or_tombstone!
    sign_in admin

    get admin_group_path(active_group)
    filter_document = Nokogiri::HTML(response.body)
    expect(filter_document.at_css("input[name='content_q']")).to be_present
    expect(filter_document.at_css("select[name='content_status']")).to be_present
    expect(filter_document.at_css("select[name='content_sort']")).to be_present
    expect(filter_document.at_css("select[name='kind'], select[name='location']")).to be_nil

    {
      { content_q: "filter-member@example.com" } => [ book_jjaek, comment, deleted ],
      { content: "general" } => [ general, deleted ],
      { content: "book" } => [ book_jjaek ],
      { content: "comments" } => [ comment, preservation_comment ],
      { content_status: "deleted" } => [ deleted ],
      { content_q: "group_book", content: "book", content_status: "active" } => [ book_jjaek ]
    }.each do |filters, expected_records|
      get admin_group_path(active_group), params: filters
      document = Nokogiri::HTML(response.body)
      rows = document.css("#admin_group_content_timeline tbody tr")
      expected_ids = expected_records.map do |record|
        record_type = record.is_a?(Comment) ? "comment" : "jjaek"
        "group_timeline_#{record_type}_#{record.id}"
      end
      expect(rows.map { |row| row["id"] }).to match_array(expected_ids)
      expect(document.css("#admin_group_content_timeline th").map { |header| header.text.strip }).to eq(
        [ "종류", "작성자", "본문", "참고", "상태", "작성 시각", "작업" ]
      )
      active_content = filters.fetch(:content, "all")
      expect(document.at_css("nav a[aria-current='page']")["href"]).to include("content=#{active_content}")
    end

    get admin_group_path(active_group), params: {
      content: "invalid",
      content_status: "invalid",
      content_sort: "invalid",
      q: "INDEX_ONLY_QUERY",
      group_type: "private_group",
      status: "active",
      sort: "name",
      page: 2
    }
    invalid_document = Nokogiri::HTML(response.body)
    expect(invalid_document.css("#admin_group_content_timeline tbody tr").size).to eq(5)
    expect(invalid_document.at_css("nav a[aria-current='page']").text.strip).to eq("전체")
    expect(invalid_document.at_css("input[name='content_q']")["value"]).to be_blank

    get admin_group_path(active_group), params: {
      content: "comments",
      content_q: "FILTER",
      content_status: "active",
      content_sort: "oldest",
      q: "Filtered content group",
      group_type: "public_group",
      status: "active",
      sort: "name",
      page: 2,
      all_page: 2
    }
    filtered_document = Nokogiri::HTML(response.body)
    expect(filtered_document.at_css("input[name='content']")["value"]).to eq("comments")
    reset_link = filtered_document.css("a").find { |link| link.text.strip == "필터 초기화" }
    expect(reset_link["href"]).to eq(
      admin_group_path(
        active_group,
        q: "Filtered content group",
        group_type: "public_group",
        status: "active",
        sort: "name",
        page: 2,
        content: "comments"
      )
    )
    book_link = filtered_document.css("nav a").find { |link| link.text.strip == "책짹" }
    expect(book_link["href"]).to include(
      "content=book",
      "content_q=FILTER",
      "content_status=active",
      "content_sort=oldest"
    )
    expect(book_link["href"]).not_to include("all_page")

    back_link = filtered_document.css("a").find { |link| link.text.include?("동아리 운영 관리로") }
    expect(back_link["href"]).to eq(
      admin_groups_path(
        q: "Filtered content group",
        group_type: "public_group",
        status: "active",
        sort: "name",
        page: 2
      )
    )
    expect(back_link["href"]).not_to include("content=", "content_", "all_page")
  end

  it "paginates mixed Group content chronologically at the database boundary" do
    active_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Paged content group", group_type: :public_group)
    base_time = Time.current
    source = group_admin.jjaeks.create!(
      group: active_group,
      content: "PAGED_GROUP_JJAEK_0",
      created_at: base_time
    )
    25.times do |index|
      group_admin.jjaeks.create!(
        group: active_group,
        content: "PAGED_GROUP_JJAEK_#{index + 1}",
        created_at: base_time - ((index + 1) * 2).minutes
      )
      source.comments.create!(
        user: group_admin,
        content: "PAGED_GROUP_COMMENT_#{index}",
        created_at: base_time - (index * 2 + 1).minutes
      )
    end
    sign_in admin

    get admin_group_path(active_group), params: {
      content: "all",
      content_q: "PAGED_GROUP",
      content_status: "active",
      content_sort: "recent"
    }

    first_page = Nokogiri::HTML(response.body)
    first_page_rows = first_page.css("#admin_group_content_timeline tbody tr")
    expect(first_page_rows.size).to eq(50)
    expect(first_page_rows.first(4).map(&:text).join).to match(
      /PAGED_GROUP_JJAEK_0.*PAGED_GROUP_COMMENT_0.*PAGED_GROUP_JJAEK_1.*PAGED_GROUP_COMMENT_1/m
    )
    expect(response.body).to include(
      "content=all",
      "content_q=PAGED_GROUP",
      "content_status=active",
      "content_sort=recent",
      "all_page=2"
    )

    get admin_group_path(active_group), params: {
      content: "all",
      content_q: "PAGED_GROUP",
      content_status: "active",
      content_sort: "recent",
      all_page: 2
    }
    second_page = Nokogiri::HTML(response.body)
    expect(second_page.css("#admin_group_content_timeline tbody tr").size).to eq(1)
    expect(second_page.css("#admin_group_content_timeline tbody tr").first.text).to include("PAGED_GROUP_JJAEK_25")

    get admin_group_path(active_group), params: { content_q: "PAGED_GROUP", content_sort: "oldest" }
    oldest_first = Nokogiri::HTML(response.body).css("#admin_group_content_timeline tbody tr").first
    expect(oldest_first.text).to include("PAGED_GROUP_JJAEK_25")
  end

  it "preserves every close event across repeated operations cycles" do
    sign_in admin
    patch approve_admin_group_path(group)

    sign_in group_admin
    patch close_group_path(group), params: { group: { closure_reason: "First season ended" } }
    patch request_reactivation_group_path(group)

    sign_in admin
    patch approve_admin_group_path(group)

    sign_in group_admin
    patch close_group_path(group), params: { group: { closure_reason: "Second season ended" } }
    patch request_reactivation_group_path(group)

    sign_in admin
    patch approve_admin_group_path(group)

    expect(group.lifecycle_events.operations_closed.order(:created_at, :id).pluck(:detail)).to eq([ "First season ended", "Second season ended" ])
    expect(group.lifecycle_events.reactivation_requested.count).to eq(2)
    expect(group.lifecycle_events.reactivation_approved.count).to eq(2)

    get admin_group_path(group)
    opening_position = response.body.index("동아리 개설")
    first_close_position = response.body.index("First season ended")
    reactivation_position = response.body.index("동아리 재운영")
    second_close_position = response.body.index("Second season ended")
    expect([ opening_position, first_close_position, reactivation_position, second_close_position ]).to eq(
      [ opening_position, first_close_position, reactivation_position, second_close_position ].sort
    )
    expect(response.body.scan("동아리 재운영").size).to eq(2)
    expect(response.body).to include("운영 종료 사유", "First season ended", "Second season ended")
  end

  it "does not approve a group that is not pending" do
    group.active!
    sign_in admin

    patch approve_admin_group_path(group)

    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_active
  end
end
