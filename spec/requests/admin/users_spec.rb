require "rails_helper"

RSpec.describe "Admin user inventory", type: :request do
  let!(:admin) { User.create!(name: "Global Admin", email: "global-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Alpha Reader", email: "alpha@example.com", password: "password123!", created_at: 3.days.ago) }
  let!(:withdrawn) { User.create!(name: "Withdrawn Reader", email: "withdrawn@example.com", password: "password123!") }

  before do
    withdrawn.update_columns(
      email: "withdrawn-#{withdrawn.id}-replacement@users.invalid",
      withdrawn_at: 1.day.ago
    )
  end

  def listed_ids
    Nokogiri::HTML(response.body).css("tbody tr").filter_map { |row| row["id"]&.delete_prefix("user_")&.to_i }
  end

  def application_nav_links
    Nokogiri::HTML(response.body).css("header nav a").to_h { |link| [ link.text.strip, link["href"] ] }
  end

  it "shows direct inventory links in the application nav only to global admins" do
    sign_in admin
    get root_path
    expect(application_nav_links).to include(
      "사용자 관리" => admin_users_path,
      "동아리 운영 관리" => admin_groups_path
    )
    expect(application_nav_links).not_to have_key("운영 관리")

    sign_in reader
    get root_path
    expect(application_nav_links).not_to have_key("사용자 관리")
    expect(application_nav_links).not_to have_key("동아리 운영 관리")

    Group.create!(group_admin: reader, name: "Reader managed", group_type: :public_group, application_purpose: "Read")
    get root_path
    expect(application_nav_links).not_to have_key("사용자 관리")
    expect(application_nav_links).not_to have_key("동아리 운영 관리")
  end

  it "does not repeat inventory switching navigation inside admin pages" do
    group = Group.create!(group_admin: reader, name: "Admin detail check", group_type: :public_group, application_purpose: "Read")
    sign_in admin

    [ admin_users_path, admin_user_path(reader), admin_groups_path, admin_group_path(group) ].each do |path|
      get path
      document = Nokogiri::HTML(response.body)
      expect(document.css("main nav a[href='#{admin_users_path}'], main nav a[href='#{admin_groups_path}']")).to be_empty
    end
  end

  it "allows only a global admin to access the list and details" do
    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)

    Group.create!(group_admin: reader, name: "Managed by reader", group_type: :public_group, application_purpose: "Read")
    sign_in reader
    get admin_users_path
    expect(response).to redirect_to(root_path)
    get admin_user_path(admin)
    expect(response).to redirect_to(root_path)

    sign_in admin
    get admin_users_path
    expect(response).to have_http_status(:ok)
    get admin_user_path(reader)
    expect(response).to have_http_status(:ok)
  end

  it "combines name or email search with account and role filters" do
    sign_in admin
    get admin_users_path, params: { q: "alpha@", status: "active", role: "regular" }
    expect(listed_ids).to eq([ reader.id ])

    get admin_users_path, params: { q: "Withdrawn", status: "withdrawn" }
    expect(listed_ids).to eq([ withdrawn.id ])

    get admin_users_path, params: { role: "global_admin" }
    expect(listed_ids).to eq([ admin.id ])
  end

  it "filters non-exclusive global admin and group admin roles and regular users" do
    Group.create!(group_admin: admin, name: "Admin club", group_type: :public_group, application_purpose: "Read")
    Group.create!(group_admin: reader, name: "Reader club", group_type: :public_group, application_purpose: "Read")
    sign_in admin

    get admin_users_path, params: { role: "global_admin" }
    expect(listed_ids).to contain_exactly(admin.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("Global admin")

    get admin_users_path, params: { role: "group_admin" }
    expect(listed_ids).to contain_exactly(admin.id, reader.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("Global admin", "동아리 관리자")

    get admin_users_path, params: { role: "regular" }
    expect(listed_ids).to contain_exactly(withdrawn.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{withdrawn.id}").text).to include("일반 사용자")
  end

  it "hides the withdrawn replacement email while retaining lifecycle details" do
    sign_in admin
    get admin_users_path, params: { status: "withdrawn" }

    row = Nokogiri::HTML(response.body).at_css("#user_#{withdrawn.id}")
    expect(row.text).to include("본인 탈퇴")
    expect(row.at_css('[data-field="email"]').text.strip).to eq("-")
    expect(row.text).not_to include(withdrawn.email)

    get admin_user_path(withdrawn)
    detail = Nokogiri::HTML(response.body)
    email_label = detail.css("dt").find { |node| node.text.strip == I18n.t("admin.users.fields.email") }
    expect(response.body).to include("본인 탈퇴", I18n.l(withdrawn.withdrawn_at, format: :short))
    expect(email_label.next_element.text.strip).to eq("-")
    expect(response.body).not_to include(withdrawn.email)

    get admin_users_path, params: { q: reader.email }
    expect(Nokogiri::HTML(response.body).at_css("#user_#{reader.id} [data-field='email']").text.strip).to eq(reader.email)
  end

  it "supports whitelisted sorting and falls back safely" do
    sign_in admin
    get admin_users_path, params: { sort: "name" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "oldest" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "recent" }
    expect(listed_ids.first).to eq(withdrawn.id)
    get admin_users_path, params: { sort: "invalid" }
    expect(listed_ids.first).to eq(withdrawn.id)
  end

  it "paginates without losing filters and handles invalid values safely" do
    49.times { |index| User.create!(name: "Paged #{index}", email: "paged-#{index}@example.com", password: "password123!") }
    sign_in admin

    get admin_users_path, params: { q: "example.com", page: 2, sort: "unknown", status: "unknown" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(1)
    expect(response.body).to include("q=example.com", "page=1")

    get admin_users_path, params: { page: "invalid", from: "ignored", to: "ignored", role: "invalid" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(50)

    get admin_users_path, params: { page: 999 }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(2)
  end

  it "shows the user's personal and Group content with direct links without exposing secrets" do
    group_admin = User.create!(name: "Content group admin", email: "content-group-admin@example.com", password: "password123!")
    target_user = User.create!(name: "Target reader", email: "target-reader@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Reader club", group_type: :private_group)
    book = Book.create!(title: "Admin detail book", authors_text: "Author")
    personal_jjaek = reader.jjaeks.create!(content: "USER_PERSONAL_CONTENT", visibility: :private_jjaek)
    targeted_jjaek = reader.jjaeks.create!(target_user:, content: "USER_TARGETED_CONTENT")
    book_jjaek = reader.jjaeks.create!(book:, content: "USER_BOOK_CONTENT", visibility: :book_friends)
    source = group_admin.jjaeks.create!(content: "USER_REQUOTE_SOURCE")
    requote = reader.jjaeks.create!(content: "USER_REQUOTE_CONTENT", quoted_jjaek: source)
    deleted_source = group_admin.jjaeks.create!(content: "DELETED_REQUOTE_SOURCE")
    deleted_source_requote = reader.jjaeks.create!(content: "DELETED_SOURCE_REQUOTE", quoted_jjaek: deleted_source)
    deleted_source.destroy!
    group_jjaek = reader.jjaeks.create!(group:, content: "USER_GROUP_CONTENT")
    group_book_jjaek = reader.jjaeks.create!(group:, book:, content: "USER_GROUP_BOOK_CONTENT")
    deleted_jjaek = reader.jjaeks.create!(content: "USER_DELETED_CONTENT")
    deleted_jjaek.comments.create!(user: group_admin, content: "PRESERVE_DELETED_JJAEK")
    deleted_jjaek.destroy_or_tombstone!
    comment = source.comments.create!(user: reader, content: "USER_COMMENT_CONTENT")
    deleted_comment_source = group_admin.jjaeks.create!(content: "DELETED_COMMENT_SOURCE")
    deleted_source_comment = deleted_comment_source.comments.create!(user: reader, content: "COMMENT_ON_DELETED_SOURCE")
    deleted_comment_source.destroy_or_tombstone!
    other_jjaek = group_admin.jjaeks.create!(content: "OTHER_USER_CONTENT")
    sign_in admin
    get admin_user_path(reader)

    document = Nokogiri::HTML(response.body)
    timeline = document.at_css("#admin_user_content_timeline")
    expect(timeline).to be_present
    expect(timeline.css("th").map { |header| header.text.strip }).to eq(
      [ "종류", "위치", "본문", "참고", "상태", "작성 시각", "작업" ]
    )
    kinds = timeline.css("[data-content-kind]").map { |row| row["data-content-kind"] }
    expect(kinds).to include("general", "book", "requote", "comments")

    personal_row = timeline.at_css("#timeline_jjaek_#{personal_jjaek.id}")
    targeted_row = timeline.at_css("#timeline_jjaek_#{targeted_jjaek.id}")
    book_row = timeline.at_css("#timeline_jjaek_#{book_jjaek.id}")
    requote_row = timeline.at_css("#timeline_jjaek_#{requote.id}")
    deleted_source_row = timeline.at_css("#timeline_jjaek_#{deleted_source_requote.id}")
    group_row = timeline.at_css("#timeline_jjaek_#{group_jjaek.id}")
    comment_row = timeline.at_css("#timeline_comment_#{comment.id}")
    deleted_comment_source_row = timeline.at_css("#timeline_comment_#{deleted_source_comment.id}")

    expect(personal_row.at_css("[data-field='location']").text.strip).to eq("일반")
    expect(personal_row.at_css("[data-field='reference']").text.strip).to eq("-")
    expect(targeted_row.at_css("[data-field='reference']").text).to include("대상", target_user.name)
    expect(targeted_row.at_css("a[href='#{admin_user_path(target_user)}']")).to be_present
    expect(group_row.at_css("[data-field='location']").text).to include("동아리", group.name)
    expect(group_row.at_css("a[href='#{admin_group_path(group)}']")).to be_present
    expect(book_row.at_css("[data-field='reference']").text).to include("책", book.title)
    expect(book_row.at_css("a[href='#{book_path(book)}']")).to be_present
    expect(requote_row.at_css("[data-field='reference']").text).to include("원문", group_admin.name, source.content)
    expect(requote_row.at_css("a[href='#{admin_user_path(group_admin)}']")).to be_present
    expect(deleted_source_row.at_css("[data-field='reference']").text.strip).to eq("-")
    expect(comment_row.at_css("[data-field='reference']").text).to include("원문", group_admin.name, source.content)
    expect(comment_row.at_css("[data-field='reference']").text).not_to include("짹 ·", "책짹 ·", "다시짹 ·")
    expect(deleted_comment_source_row.at_css("[data-field='reference']").text).to include(group_admin.name, "-")
    expect(timeline.at_css("#timeline_jjaek_#{deleted_jjaek.id} [data-field='status']").text.strip).to eq("삭제")
    expect(personal_row.at_css("[data-field='status']").text.strip).to eq("-")
    expect(personal_row.at_css("[data-field='actions'] a").text.strip).to eq("바로가기")
    expect(personal_row.at_css("a[href='#{jjaek_path(personal_jjaek)}']")).to be_present
    comment_anchor = ActionView::RecordIdentifier.dom_id(comment)
    expect(comment_row.at_css("a[href='#{jjaek_path(source, anchor: comment_anchor)}']")).to be_present
    expect(response.body).not_to include(other_jjaek.content)
    expect(response.body).not_to include(reader.encrypted_password, "reset_password_token")
  end

  it "navigates content kinds while preserving filters and using one table" do
    group_admin = User.create!(name: "Filter group admin", email: "filter-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Filter club", group_type: :private_group)
    book = Book.create!(title: "Filter book", authors_text: "Author")
    personal = reader.jjaeks.create!(content: "FILTER_PERSONAL_MATCH")
    group_general = reader.jjaeks.create!(group:, content: "FILTER_GROUP_MATCH")
    book_jjaek = reader.jjaeks.create!(book:, content: "FILTER_BOOK_MATCH")
    source = group_admin.jjaeks.create!(content: "FILTER_SOURCE")
    requote = reader.jjaeks.create!(quoted_jjaek: source, content: "FILTER_REQUOTE_MATCH")
    comment = source.comments.create!(user: reader, content: "FILTER_COMMENT_MATCH")
    deleted = reader.jjaeks.create!(content: "FILTER_DELETED_MATCH")
    deleted.comments.create!(user: group_admin, content: "PRESERVE_FILTER_DELETED")
    deleted.destroy_or_tombstone!
    sign_in admin

    get admin_user_path(reader)
    document = Nokogiri::HTML(response.body)
    navigation = document.at_css("nav[aria-label='작성 콘텐츠 종류']")
    expect(navigation.css("a").map { |link| link.text.strip }).to eq(
      [ "전체", "짹", "책짹", "다시짹", "댓글" ]
    )
    expect(navigation.at_css("a[aria-current='page']").text.strip).to eq("전체")
    expect(document.at_css("select[name='kind']")).to be_nil
    expect(document.at_css("input[name='q']")).to be_present
    expect(document.at_css("select[name='location']")).to be_present
    expect(document.at_css("select[name='status']")).to be_present
    expect(document.at_css("select[name='sort']")).to be_present

    {
      { q: "personal_match" } => [ personal ],
      { content: "general" } => [ personal, group_general, deleted ],
      { content: "book" } => [ book_jjaek ],
      { content: "requote" } => [ requote ],
      { content: "comments" } => [ comment ],
      { location: "group" } => [ group_general ],
      { status: "deleted" } => [ deleted ],
      { q: "group_match", content: "general", location: "group", status: "active" } => [ group_general ]
    }.each do |filters, expected_records|
      get admin_user_path(reader), params: filters
      filtered_document = Nokogiri::HTML(response.body)
      rows = filtered_document.css("#admin_user_content_timeline tbody tr")
      expected_ids = expected_records.map do |record|
        record_type = record.is_a?(Comment) ? "comment" : "jjaek"
        "timeline_#{record_type}_#{record.id}"
      end
      expect(rows.map { |row| row["id"] }).to match_array(expected_ids)
      expect(filtered_document.css("#admin_user_content_timeline th").map { |header| header.text.strip }).to eq(
        [ "종류", "위치", "본문", "참고", "상태", "작성 시각", "작업" ]
      )
    end

    get admin_user_path(reader), params: {
      content: "invalid",
      location: "invalid",
      status: "invalid",
      sort: "invalid",
      all_page: "invalid"
    }
    expect(response).to have_http_status(:ok)
    invalid_document = Nokogiri::HTML(response.body)
    expect(invalid_document.css("#admin_user_content_timeline tbody tr").size).to eq(6)
    expect(invalid_document.at_css("nav a[aria-current='page']").text.strip).to eq("전체")

    get admin_user_path(reader), params: {
      content: "comments",
      q: "FILTER",
      location: "group",
      status: "active",
      sort: "oldest",
      all_page: 3
    }
    filtered_document = Nokogiri::HTML(response.body)
    expect(filtered_document.at_css("input[name='content']")["value"]).to eq("comments")
    reset_link = filtered_document.css("a").find { |link| link.text.strip == "필터 초기화" }
    expect(reset_link["href"]).to eq(admin_user_path(reader, content: "comments"))
    book_link = filtered_document.css("nav a").find { |link| link.text.strip == "책짹" }
    expect(book_link["href"]).to include(
      "content=book", "q=FILTER", "location=group", "status=active", "sort=oldest"
    )
    expect(book_link["href"]).not_to include("all_page")
  end

  it "orders and paginates the mixed content timeline at the database boundary" do
    group_admin = User.create!(name: "Pagination author", email: "pagination-author@example.com", password: "password123!")
    comment_source = group_admin.jjaeks.create!(content: "PAGINATION_COMMENT_SOURCE")
    base_time = Time.current
    26.times do |index|
      reader.jjaeks.create!(content: "PAGED_GENERAL_#{index}", created_at: base_time - (index * 2).minutes)
    end
    25.times do |index|
      comment_source.comments.create!(
        user: reader,
        content: "PAGED_COMMENT_#{index}",
        created_at: base_time - (index * 2 + 1).minutes
      )
    end
    sign_in admin

    get admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "recent" }
    first_page = Nokogiri::HTML(response.body)
    first_page_rows = first_page.css("#admin_user_content_timeline tbody tr")
    expect(first_page_rows.size).to eq(50)
    expect(first_page_rows.first(4).map(&:text).join).to match(
      /PAGED_GENERAL_0.*PAGED_COMMENT_0.*PAGED_GENERAL_1.*PAGED_COMMENT_1/m
    )
    expect(response.body).to include("content=all", "q=PAGED", "sort=recent", "all_page=2")

    get admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "recent", all_page: 2 }
    second_page = Nokogiri::HTML(response.body)
    expect(second_page.css("#admin_user_content_timeline tbody tr").size).to eq(1)
    expect(second_page.css("#admin_user_content_timeline tbody tr").first.text).to include("PAGED_GENERAL_25")

    get admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "oldest" }
    oldest_first = Nokogiri::HTML(response.body).css("#admin_user_content_timeline tbody tr").first
    expect(oldest_first.text).to include("PAGED_GENERAL_25")
  end
end
