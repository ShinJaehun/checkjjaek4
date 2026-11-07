require "rails_helper"

RSpec.describe "Admin user inventory", type: :request do
  let!(:admin) { User.create!(name: "Global Admin", email: "global-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Alpha Reader", email: "alpha@example.com", password: "password123!", created_at: 3.days.ago) }
  let!(:withdrawn) { User.create!(name: "Withdrawn Reader", email: "withdrawn@example.com", password: "password123!") }

  before do
    withdrawn.update_columns(
      email: "withdrawn-#{withdrawn.id}-replacement@users.invalid",
      withdrawn_at: Time.current
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
      "소식" => root_path,
      "사용자 관리" => admin_users_path,
      "동아리 관리" => admin_groups_path
    )
    expect(application_nav_links).not_to have_key("홈")
    expect(application_nav_links).not_to have_key("운영 관리")
    expect(Nokogiri::HTML(response.body).css("#mobile-navigation-links > span[aria-hidden='true']").size).to eq(1)

    sign_in reader
    get root_path
    expect(application_nav_links).to include("소식" => root_path)
    expect(application_nav_links).not_to have_key("사용자 관리")
    expect(application_nav_links).not_to have_key("동아리 관리")
    expect(Nokogiri::HTML(response.body).css("#mobile-navigation-links > span[aria-hidden='true']")).to be_empty

    Group.create!(group_admin: reader, name: "Reader managed", group_type: :public_group, application_purpose: "Read")
    get root_path
    expect(application_nav_links).not_to have_key("사용자 관리")
    expect(application_nav_links).not_to have_key("동아리 관리")
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
    get content_admin_user_path(reader)
    expect(response).to redirect_to(new_user_session_path)

    Group.create!(group_admin: reader, name: "Managed by reader", group_type: :public_group, application_purpose: "Read")
    sign_in reader
    get admin_users_path
    expect(response).to redirect_to(root_path)
    get admin_user_path(admin)
    expect(response).to redirect_to(root_path)
    get content_admin_user_path(admin)
    expect(response).to redirect_to(root_path)

    sign_in admin
    get admin_users_path
    expect(response).to have_http_status(:ok)
    get admin_user_path(reader)
    expect(response).to have_http_status(:ok)
    get content_admin_user_path(reader)
    expect(response).to have_http_status(:ok)
  end

  it "presents identity, Group relationships, moderation, and history" do
    managed_group = Group.create!(
      lifecycle_status: :active,
      group_admin: reader,
      name: "Reader managed club",
      group_type: :public_group
    )
    membership_group = Group.create!(
      lifecycle_status: :active,
      group_admin: admin,
      name: "Reader membership club",
      group_type: :public_group
    )
    GroupMembership.create!(group: membership_group, user: reader, status: :active)
    sign_in admin

    get admin_user_path(reader)
    document = Nokogiri::HTML(response.body)
    identity = document.at_css("#admin_user_identity")
    group_relationships = document.at_css("#group_relationships")

    expect(identity.at_css("img")['alt']).to eq(reader.name)
    expect(identity.text).to include(reader.name, reader.email, "정상", "동아리 관리자")
    expect(identity.at_css("[data-field='joined-at']").text).to include(I18n.l(reader.created_at, format: :short))
    expect(identity.at_css("[data-field='suspended-at']")).to be_nil
    expect(identity.at_css("[data-field='withdrawn-at']")).to be_nil
    expect(identity.at_css("[data-role='group-admin']")).to be_present
    expect(identity.at_css("[data-role='group-admin']")["class"]).to include("bg-sky-100")
    expect(identity.at_css("[data-field='account-status']")["class"]).to include("bg-emerald-100")
    expect(identity.at_css("[data-role='regular']")).to be_nil
    expect(identity.at_css("a[href='#{content_admin_user_path(reader)}']")).to be_present
    expect(identity.at_css("a[href='#{content_admin_user_path(reader)}']").text.strip).to eq("사용자 활동")
    expect(document.at_css("#account_information, [data-field='user-id']")).to be_nil
    expect(document.text).not_to include("수정 시각")
    expect(group_relationships.at_css("#administered_groups a[href='#{admin_group_path(managed_group)}']").text.strip).to eq(managed_group.name)
    expect(group_relationships.at_css("#joined_groups a[href='#{admin_group_path(membership_group)}']").text.strip).to eq(membership_group.name)
    expect(group_relationships.at_css("#joined_groups a[href='#{admin_group_path(managed_group)}']").text.strip).to eq(managed_group.name)
    expect(group_relationships.at_css("[data-membership-status]")).to be_nil
    expect(document.at_css("a[href='#{new_admin_user_account_suspension_path(reader)}']").text.strip).to eq("계정 정지")
    expect(document.at_css("form[action*='account_suspensions']")).to be_nil
    expect(document.at_css("textarea[name='moderation_action[internal_note]']")).to be_nil
    expect(document.at_css("#account_history [data-account-event='joined']")).to be_present

    get content_admin_user_path(reader)
    activity_identity = Nokogiri::HTML(response.body).at_css("#admin_user_identity")
    expect(activity_identity.at_css("img")['alt']).to eq(reader.name)
    expect(activity_identity.text).to include(reader.name, reader.email, "정상", "동아리 관리자")
    expect(activity_identity.at_css("[data-field='joined-at']").text).to include(I18n.l(reader.created_at, format: :short))
    expect(activity_identity.at_css("[data-role='group-admin']")).to be_present
    expect(activity_identity.at_css("[data-role='regular']")).to be_nil
    expect(activity_identity.at_css("[data-field='suspended-at']")).to be_nil
    expect(activity_identity.at_css("[data-field='withdrawn-at']")).to be_nil
    expect(activity_identity.at_css("a[href='#{admin_user_path(reader)}']").text.strip).to eq("상세 보기")
    expect(activity_identity.text).not_to match(/translation missing/i)

    get admin_user_path(admin)
    admin_identity = Nokogiri::HTML(response.body).at_css("#admin_user_identity")
    expect(admin_identity.at_css("[data-role='global-admin']")).to be_present
    expect(admin_identity.at_css("[data-role='global-admin']").text.strip).to eq("시스템 관리자")
    expect(admin_identity.at_css("[data-role='global-admin']")["class"]).to include("bg-amber-100")
    expect(admin_identity.at_css("[data-role='group-admin']")).to be_present

    get content_admin_user_path(admin)
    admin_activity_identity = Nokogiri::HTML(response.body).at_css("#admin_user_identity")
    expect(admin_activity_identity.at_css("[data-role='global-admin']")).to be_present
    expect(admin_activity_identity.at_css("[data-role='group-admin']")).to be_present

    get admin_user_path(withdrawn)
    withdrawn_document = Nokogiri::HTML(response.body)
    expect(withdrawn_document.at_css("#admin_user_identity [data-role='regular']")).to be_present
    expect(withdrawn_document.at_css("#admin_user_identity [data-role='regular']")["class"]).to include("bg-stone-100")
    expect(withdrawn_document.at_css("#admin_user_identity [data-field='account-status']")["class"]).to include("bg-stone-200")
    expect(withdrawn_document.at_css("#administered_groups").text).to include("관리 중인 동아리가 없습니다.")
    expect(withdrawn_document.at_css("#joined_groups").text).to include("참여 중인 동아리가 없습니다.")

    get content_admin_user_path(withdrawn)
    withdrawn_activity_identity = Nokogiri::HTML(response.body).at_css("#admin_user_identity")
    expect(withdrawn_activity_identity.at_css("[data-role='regular']")).to be_present
    expect(withdrawn_activity_identity.at_css("[data-field='account-status']").text.strip).to eq("본인 탈퇴")
    expect(withdrawn_activity_identity.at_css("[data-field='email']").text.strip).to eq("-")
    expect(withdrawn_activity_identity.at_css("[data-field='withdrawn-at']").text).to include(
      I18n.l(withdrawn.withdrawn_at, format: :short)
    )
    expect(withdrawn_activity_identity.at_css("[data-field='suspended-at']")).to be_nil
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

  it "combines user identity details and links each latest authored content activity" do
    book = Book.create!(title: "Inventory book")
    active_group = Group.create!(
      lifecycle_status: :active,
      group_admin: reader,
      name: "Inventory activity group",
      group_type: :public_group
    )
    source = admin.jjaeks.create!(content: "Inventory requote source", created_at: 2.hours.ago)
    comment_source = admin.jjaeks.create!(content: "Inventory comment source", created_at: 90.minutes.ago)
    general_author = User.create!(name: "General author", email: "general-inventory@example.com", password: "password123!")
    book_author = User.create!(name: "Book author", email: "book-inventory@example.com", password: "password123!")
    requote_author = User.create!(name: "Requote author", email: "requote-inventory@example.com", password: "password123!")
    group_author = User.create!(name: "Group author", email: "group-inventory@example.com", password: "password123!")
    group_book_author = User.create!(name: "Group book author", email: "group-book-inventory@example.com", password: "password123!")
    comment_author = User.create!(name: "Comment author", email: "comment-inventory@example.com", password: "password123!")

    activities = {
      general_author => general_author.jjaeks.create!(content: "Inventory general", created_at: 70.minutes.ago),
      book_author => create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: book_author, content: "Inventory book", created_at: 60.minutes.ago),
      requote_author => requote_author.jjaeks.create!(quoted_jjaek: source, content: "Inventory requote", created_at: 50.minutes.ago),
      group_author => group_author.jjaeks.create!(group: active_group, content: "Inventory group", created_at: 40.minutes.ago),
      group_book_author => create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: group_book_author, group: active_group, content: "Inventory group book", created_at: 30.minutes.ago),
      comment_author => comment_source.comments.create!(user: comment_author, content: "Inventory comment", created_at: 20.minutes.ago)
    }
    expected_kinds = [ "짹", "짹", "다시짹", "동아리짹", "동아리짹", "댓글" ]

    sign_in admin
    get admin_users_path
    document = Nokogiri::HTML(response.body)

    header = document.at_css("#admin_user_inventory_header")
    expect(header).to be_present
    expect(header.at_css("h1").text.strip).to eq("사용자 관리")
    expect(header.text).to include("사용자 계정과 상태를 검색하고 확인합니다.")
    expect(header.at_css("form")).to be_nil
    controls = document.at_css("#admin_user_inventory_controls")
    expect(controls).to be_present
    expect(controls.at_css("form")).to be_present
    expect(controls.at_css("h1")).to be_nil
    expect(controls.at_css("input[type='submit']")["value"]).to eq("검색")
    expect(controls.css("a").map { |link| link.text.strip }).to include("조건 초기화")
    expect(controls.at_css("select[name='role'] option[value='global_admin']").text).to eq("시스템 관리자")
    expect(document.at_css("#admin_user_inventory_table")).to be_present
    expect(document.css("#admin_user_inventory_table th").map { |header| header.text.strip }).to eq(
      [ "사용자", "계정 상태", "권한", "최근 활동", "가입 시각", "작업" ]
    )
    identity = document.at_css("#user_#{reader.id} [data-field='user']")
    expect(identity.text).to include(reader.name, reader.email)
    expect(identity.at_css("img")['alt']).to eq(reader.name)
    expect(document.at_css("#user_#{withdrawn.id} [data-field='user'] [data-field='email']").text.strip).to eq("-")
    expect(document.at_css("#user_#{withdrawn.id} [data-field='latest-activity']").text.strip).to eq("-")
    expect(document.at_css("#user_#{reader.id} [data-field='account-status']")["class"]).to include("bg-emerald-100")
    expect(document.at_css("#user_#{withdrawn.id} [data-field='account-status']")["class"]).to include("bg-stone-200")
    expect(document.at_css("#user_#{reader.id} a[href='#{admin_user_path(reader)}']")).to be_present
    expect(document.at_css("#user_#{reader.id} a[href='#{admin_user_path(reader)}']").text.strip).to eq("상세")
    expect(document.at_css("#user_#{reader.id} a[href='#{content_admin_user_path(reader)}']").text.strip).to eq("활동")

    expected_kind_colors = %w[bg-sky-100 bg-sky-100 bg-violet-100 bg-emerald-100 bg-emerald-100 bg-amber-100]
    activities.each_with_index do |(author, activity), index|
      cell = document.at_css("#user_#{author.id} [data-field='latest-activity']")
      expected_path = activity.is_a?(Comment) ? jjaek_path(activity.jjaek, anchor: "comment_#{activity.id}") : jjaek_path(activity)
      expect(cell.text).to include(expected_kinds[index], I18n.l(activity.created_at, format: :short))
      expect(cell.at_css("a")['href']).to eq(expected_path)
      expect(cell.at_css("[data-activity-kind]")["class"]).to include(expected_kind_colors[index])
    end
  end

  it "filters suspended users separately from active and withdrawn users" do
    reader.update!(suspended_at: Time.current)
    sign_in admin

    get admin_users_path, params: { status: "suspended" }
    expect(listed_ids).to eq([ reader.id ])
    expect(Nokogiri::HTML(response.body).at_css("#user_#{reader.id} [data-field='account-status']")["class"]).to include("bg-red-100")

    get admin_user_path(reader)
    detail = Nokogiri::HTML(response.body)
    expect(detail.at_css("#admin_user_identity [data-field='account-status']")["class"]).to include("bg-red-100")
    expect(detail.at_css("section.border-amber-200 span.rounded-full")["class"]).to include("bg-red-100")

    get admin_users_path, params: { status: "active" }
    expect(listed_ids).to contain_exactly(admin.id)
  end

  it "filters non-exclusive global admin and group admin roles and regular users" do
    Group.create!(group_admin: admin, name: "Admin club", group_type: :public_group, application_purpose: "Read")
    Group.create!(group_admin: reader, name: "Reader club", group_type: :public_group, application_purpose: "Read")
    sign_in admin

    get admin_users_path, params: { role: "global_admin" }
    expect(listed_ids).to contain_exactly(admin.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("시스템 관리자")

    get admin_users_path, params: { role: "group_admin" }
    expect(listed_ids).to contain_exactly(admin.id, reader.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("시스템 관리자", "동아리 관리자")

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
    expect(response.body).to include("본인 탈퇴", I18n.l(withdrawn.withdrawn_at, format: :short))
    expect(detail.at_css("#admin_user_identity [data-field='email']").text.strip).to eq("-")
    expect(detail.at_css("#admin_user_identity [data-field='withdrawn-at']").text).to include(
      I18n.l(withdrawn.withdrawn_at, format: :short)
    )
    expect(detail.at_css("#admin_user_identity [data-field='suspended-at']")).to be_nil
    expect(response.body).not_to include(withdrawn.email)
    expect(detail.css("#account_history [data-account-event]").map { |entry| entry["data-account-event"] }).to eq(
      %w[joined withdrawn]
    )

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
    expect(listed_ids.size).to eq(21)
    expect(response.body).to include("q=example.com", "page=1")

    get admin_users_path, params: { page: "invalid", from: "ignored", to: "ignored", role: "invalid" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(30)

    get admin_users_path, params: { page: 999 }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(22)
  end

  it "shows the user's personal and Group content with direct links without exposing secrets" do
    group_admin = User.create!(name: "Content group admin", email: "content-group-admin@example.com", password: "password123!")
    target_user = User.create!(name: "Target reader", email: "target-reader@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Reader club", group_type: :private_group)
    book = Book.create!(title: "Admin detail book", authors_text: "Author")
    personal_jjaek = reader.jjaeks.create!(content: "USER_PERSONAL_CONTENT", visibility: :private_jjaek)
    targeted_jjaek = reader.jjaeks.create!(target_user:, content: "USER_TARGETED_CONTENT")
    book_jjaek = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: reader, content: "USER_BOOK_CONTENT", visibility: :book_friends)
    4.times do |index|
      book_jjaek.jjaek_book_attachments.create!(book: Book.create!(title: "Extra attachment #{index}"), position: index + 1)
    end
    source = group_admin.jjaeks.create!(content: "USER_REQUOTE_SOURCE")
    requote = reader.jjaeks.create!(content: "USER_REQUOTE_CONTENT", quoted_jjaek: source)
    deleted_source = group_admin.jjaeks.create!(content: "DELETED_REQUOTE_SOURCE")
    deleted_source_requote = reader.jjaeks.create!(content: "DELETED_SOURCE_REQUOTE", quoted_jjaek: deleted_source)
    deleted_source.destroy!
    group_jjaek = reader.jjaeks.create!(group:, content: "USER_GROUP_CONTENT")
    group_book_jjaek = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: reader, group:, content: "USER_GROUP_BOOK_CONTENT")
    deleted_jjaek = reader.jjaeks.create!(content: "USER_DELETED_CONTENT")
    deleted_jjaek.comments.create!(user: group_admin, content: "PRESERVE_DELETED_JJAEK")
    deleted_jjaek.destroy_or_tombstone!
    hidden_jjaek = reader.jjaeks.create!(content: "USER_HIDDEN_CONTENT")
    Jjaeks::Hide.new(hidden_jjaek, actor: admin, public_reason: "other").call!
    comment = source.comments.create!(user: reader, content: "USER_COMMENT_CONTENT")
    hidden_comment = source.comments.create!(user: reader, content: "USER_HIDDEN_COMMENT_CONTENT")
    Comments::Hide.new(hidden_comment, actor: admin, public_reason: "other").call!
    deleted_comment_source = group_admin.jjaeks.create!(content: "DELETED_COMMENT_SOURCE")
    deleted_source_comment = deleted_comment_source.comments.create!(user: reader, content: "COMMENT_ON_DELETED_SOURCE")
    deleted_comment_source.destroy_or_tombstone!
    other_jjaek = group_admin.jjaeks.create!(content: "OTHER_USER_CONTENT")
    sign_in admin
    get admin_user_path(reader)

    detail = Nokogiri::HTML(response.body)
    expect(detail.at_css("#admin_user_content_timeline")).to be_nil
    expect(detail.at_css("#admin_user_identity a[href='#{content_admin_user_path(reader)}']").text.strip).to eq("사용자 활동")

    get content_admin_user_path(reader)

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#admin_user_identity")).to be_present
    expect(document.at_css("#admin_user_identity").parent["class"].split).to include("mx-auto", "max-w-5xl")
    expect(document.at_css("#admin_user_identity a[href='#{admin_user_path(reader)}']").text.strip).to eq("상세 보기")
    expect(document.text).not_to match(/translation missing/i)
    controls = document.at_css("#admin_user_activity_controls")
    expect(controls).to be_present
    expect(controls.at_css("h2").text.strip).to eq("사용자 활동")
    expect(controls.text).not_to include("이 사용자가 작성한 짹과 댓글을 영역·유형별로 확인합니다.")
    expect(controls.text).to match(/전체 \d+건/)
    expect(controls.css("span").map { |label| label.text.strip }).to include("영역", "유형")
    expect(controls.at_css("nav[aria-label='영역']")).to be_present
    expect(controls.at_css("nav[aria-label='유형']")).to be_present
    expect(controls.at_css("form")).to be_present
    expect(controls.at_css("input[type='submit']")["value"]).to eq("검색")
    expect(controls.css("a").map { |link| link.text.strip }).to include("조건 초기화")
    timeline = document.at_css("#admin_user_content_timeline")
    expect(timeline).to be_present
    expect(timeline.at_css("form")).to be_nil
    expect(timeline.css("th").map { |header| header.text.strip }).to eq(
      [ "유형", "영역", "본문", "상태", "작성 시각", "작업" ]
    )
    kinds = timeline.css("[data-content-kind]").map { |row| row["data-content-kind"] }
    expect(kinds).to include("general", "group_general", "comments")

    personal_row = timeline.at_css("#timeline_jjaek_#{personal_jjaek.id}")
    targeted_row = timeline.at_css("#timeline_jjaek_#{targeted_jjaek.id}")
    book_row = timeline.at_css("#timeline_jjaek_#{book_jjaek.id}")
    requote_row = timeline.at_css("#timeline_jjaek_#{requote.id}")
    deleted_source_row = timeline.at_css("#timeline_jjaek_#{deleted_source_requote.id}")
    group_row = timeline.at_css("#timeline_jjaek_#{group_jjaek.id}")
    comment_row = timeline.at_css("#timeline_comment_#{comment.id}")
    deleted_comment_source_row = timeline.at_css("#timeline_comment_#{deleted_source_comment.id}")

    expect(personal_row.at_css("[data-field='location']").text.strip).to eq("개인")
    expect(personal_row.at_css("[data-field='metadata']")).to be_nil
    expect(personal_row.at_css("[data-field='reference']")).to be_nil
    expect(targeted_row.at_css("[data-field='reference']")).to be_nil
    expect(targeted_row.text).not_to include(target_user.name)
    group_location = group_row.at_css("[data-field='location']")
    expect(group_location.at_css("div").text.strip).to eq("동아리")
    expect(group_location.at_css("a[href='#{admin_group_path(group)}']").text.strip).to eq(group.name)
    expect(group_location.text).not_to include("·")
    expect(book_row.at_css("[data-field='metadata']").text).to include("#{book.title} 외 4권")
    expect(book_row.text).not_to include("Extra attachment")
    expect(group_row.at_css("td").text.strip).to eq("동아리짹")
    expect(group_row.at_css("[data-field='body']").text).not_to include(group.name)
    expect(personal_row.at_css("[data-activity-kind='general']")["class"]).to include("bg-sky-100")
    expect(book_row.at_css("[data-activity-kind='general']")["class"]).to include("bg-sky-100")
    expect(group_row.at_css("[data-activity-kind='group_general']").text.strip).to eq("동아리짹")
    expect(group_row.at_css("[data-activity-kind='group_general']")["class"]).to include("bg-emerald-100")
    expect(timeline.at_css("#timeline_jjaek_#{group_book_jjaek.id} [data-activity-kind='group_general']").text.strip).to eq("동아리짹")
    expect(comment_row.at_css("[data-activity-kind='comments']")["class"]).to include("bg-amber-100")
    expect(book_row.at_css("a[href='#{book_path(book)}']")).to be_nil
    expect(requote_row.css("[data-activity-kind]").map { |badge| badge.text.strip }).to eq([ "다시짹" ])
    expect(requote_row.at_css("[data-activity-kind='requote']")["class"]).to include("bg-violet-100")
    expect(requote_row.at_css("[data-field='metadata']").text).to include("#{group_admin.name} : #{source.content}")
    expect(deleted_source_row.at_css("[data-activity-kind='requote']").text.strip).to eq("다시짹")
    expect(deleted_source_row.at_css("[data-field='metadata']")).to be_nil
    expect(comment_row.at_css("[data-field='metadata']").text).to include("#{group_admin.name} : #{source.content}")
    expect(deleted_comment_source_row.at_css("[data-field='metadata']")).to be_nil
    expect(deleted_comment_source_row.at_css("[data-field='reference']")).to be_nil
    expect(timeline.css("[data-field='reference']")).to be_empty
    expect(timeline.at_css("#timeline_jjaek_#{deleted_jjaek.id} [data-field='status']").text.strip).to eq("삭제됨")
    expect(timeline.at_css("#timeline_jjaek_#{deleted_jjaek.id} [data-field='metadata']")).to be_nil
    expect(timeline.at_css("#timeline_jjaek_#{deleted_jjaek.id} [data-field='status'] span")["class"]).to include("bg-stone-200")
    expect(timeline.at_css("#timeline_jjaek_#{hidden_jjaek.id} [data-field='status']").text.strip).to eq("숨김")
    expect(timeline.at_css("#timeline_jjaek_#{hidden_jjaek.id} [data-field='status'] span")["class"]).to include("bg-red-100")
    expect(timeline.at_css("#timeline_comment_#{hidden_comment.id} [data-field='status']").text.strip).to eq("숨김")
    expect(personal_row.at_css("[data-field='status']").text.strip).to eq("정상")
    expect(personal_row.at_css("[data-field='status'] span")["class"]).to include("bg-emerald-100")
    expect(personal_row.at_css("[data-field='actions'] a").text.strip).to eq("바로가기")
    expect(personal_row.at_css("a[href='#{jjaek_path(personal_jjaek, return_to: content_admin_user_path(reader))}']")).to be_present
    comment_anchor = ActionView::RecordIdentifier.dom_id(comment)
    expect(comment_row.at_css("a[href='#{jjaek_path(source, anchor: comment_anchor, return_to: content_admin_user_path(reader))}']")).to be_present
    expect(response.body).not_to include(other_jjaek.content)
    expect(response.body).not_to include(reader.encrypted_password, "reset_password_token")
  end

  it "classifies recommendations and requotes by location and keeps attachment metadata separate" do
    group = Group.create!(group_admin: reader, name: "Unified inventory club", lifecycle_status: :active, group_type: :public_group)
    books = 2.times.map { |index| Book.create!(title: "INVENTORY_ATTACHMENT_#{index}") }
    source = create_jjaek_with_books(legacy_source_kind: "book", books: [ books.first ], user: admin, content: "INVENTORY_SOURCE_BODY")
    recommendations = [ nil, group ].map do |destination|
      post = build_jjaek_with_books(legacy_source_kind: "recommendation", user: reader, group: destination, content: "INVENTORY_RECOMMENDATION")
      books.each_with_index { |book, position| post.jjaek_book_attachments.build(book:, position:) }
      post.save!
      post
    end
    requotes = [ nil, group ].map do |destination|
      reader.jjaeks.create!(group: destination, quoted_jjaek: source, content: "INVENTORY_REQUOTE")
    end
    sign_in admin

    { "personal" => [ recommendations.first, requotes.first ], "group" => [ recommendations.last, requotes.last ] }.each do |location, posts|
      get content_admin_user_path(reader), params: { location: location }
      document = Nokogiri::HTML(response.body)
      rows = document.css("#admin_user_content_timeline tbody tr")
      expect(rows.map { |row| row["id"] }).to match_array(posts.map { |post| "timeline_jjaek_#{post.id}" })
      expect(rows.map { |row| row["data-content-kind"] }.uniq).to match_array([ location == "group" ? "group_general" : "general", "requote" ])
      recommendation = rows.find { |row| row["id"] == "timeline_jjaek_#{posts.first.id}" }
      requote = rows.find { |row| row["id"] == "timeline_jjaek_#{posts.last.id}" }
      expect(recommendation.at_css("[data-field='metadata']").text).to include("#{books.first.title} 외 1권")
      expect(requote.at_css("[data-field='metadata']").text).to include("#{admin.name} : #{source.content}")
      expect(requote.css("[data-activity-kind]").map { |badge| badge.text.strip })
        .to eq([ "다시짹" ])
      expect(requote.at_css("[data-field='metadata']").text).not_to include(books.first.title)
      expect(rows.text).not_to include(books.last.title)
      if location == "group"
        expect(requote.at_css("td").text.strip).to eq("다시짹")
        expect(requote.at_css("[data-field='location'] a").text.strip).to eq(group.name)
        expect(requote.at_css("[data-field='body']").text).not_to include(group.name)
      end
    end

    get admin_users_path
    activity = Nokogiri::HTML(response.body).at_css("#user_#{reader.id} [data-field='latest-activity']")
    expect(activity.css("[data-activity-kind]").map { |badge| badge.text.strip }).to eq([ "다시짹" ])
    expect(activity.at_css("a")["href"]).to eq(jjaek_path(requotes.last))

    comment_parent = admin.jjaeks.create!(content: "INVENTORY_COMMENT_PARENT")
    comment_parent.comments.create!(user: reader, content: "INVENTORY_COMMENT", created_at: 1.day.ago)
    expected_counts = { "general" => 1, "group" => 1, "requote" => 2, "comments" => 1 }
    get admin_user_path(reader)
    detail = Nokogiri::HTML(response.body)
    identity = detail.at_css("#admin_user_identity")
    expect(identity.at_css("[data-field='latest-activity']")).to be_nil
    expect(detail.at_css("#admin_user_activity_summary")).to be_nil
    expect(identity.css("[data-activity-kind]")).to be_empty
    expect(identity.css("nav a").map { |link| link.text.squish })
      .to eq([ "짹 1", "동아리짹 1", "다시짹 2", "댓글 1" ])
    expected_counts.each do |type, count|
      count_element = identity.at_css("[data-activity-count='#{type}']")
      expect(count_element.text.to_i).to eq(count)
      expect(count_element.parent["href"]).to eq(content_admin_user_path(reader, content: type))
    end

    get content_admin_user_path(reader), params: { q: "INVENTORY" }
    content = Nokogiri::HTML(response.body)
    expect(content.css("[data-activity-count]")).to be_empty
    expect(content.css("nav[aria-label='유형'] a").map { |link| link.text.strip })
      .to eq([ "전체", "짹", "동아리짹", "다시짹", "댓글" ])
    expect(content.css("#admin_user_content_timeline tbody tr").size).to eq(expected_counts.values.sum)

    get content_admin_user_path(reader), params: { content: "requote", q: "INVENTORY", location: "group", status: "active" }
    filtered = Nokogiri::HTML(response.body)
    expect(filtered.css("#admin_user_content_timeline tbody tr").map { |row| row["id"] }).to eq([ "timeline_jjaek_#{requotes.last.id}" ])
    expect(filtered.at_css("#timeline_jjaek_#{requotes.last.id} [data-activity-kind='requote']")["class"])
      .to eq(activity.at_css("[data-activity-kind='requote']")["class"])
    expect(filtered.css("[data-activity-count]")).to be_empty
    expect(filtered.at_css("nav[aria-label='유형'] a[aria-current='page']").text.strip).to eq("다시짹")
    get admin_user_path(reader), params: { q: "INVENTORY", location: "group", status: "active" }
    filtered_summary = Nokogiri::HTML(response.body)
    filtered_counts = expected_counts.keys.to_h do |type|
      [ type, filtered_summary.at_css("[data-activity-count='#{type}']").text.to_i ]
    end
    expect(filtered_counts).to eq("general" => 0, "group" => 1, "requote" => 1, "comments" => 0)
    expect(filtered_counts.values.sum).to eq(2)
    expected_counts.each_key do |type|
      link = filtered_summary.at_css("[data-activity-count='#{type}']").parent
      expect(link["href"]).to eq(content_admin_user_path(reader, q: "INVENTORY", location: "group", status: "active", content: type))
    end

    source.destroy!
    get admin_user_path(reader)
    after_deletion = Nokogiri::HTML(response.body)
    expected_counts.each do |type, count|
      expect(after_deletion.at_css("[data-activity-count='#{type}']").text.to_i).to eq(count)
    end
    expect(after_deletion.at_css("#admin_user_identity [data-activity-count='requote']").parent.text.squish).to eq("다시짹 2")
  end

  it "truncates long activity and source summaries while keeping direct links" do
    source_author = User.create!(name: "Excerpt author", email: "excerpt-author@example.com", password: "password123!")
    long_content = "LONG_EXCERPT_#{'가' * 150}"
    source = source_author.jjaeks.create!(content: long_content)
    requote = reader.jjaeks.create!(content: long_content, quoted_jjaek: source)
    comment = source.comments.create!(user: reader, content: long_content)
    sign_in admin

    get content_admin_user_path(reader)
    document = Nokogiri::HTML(response.body)

    [ [ "jjaek", requote ], [ "comment", comment ] ].each do |record_type, record|
      row = document.at_css("#timeline_#{record_type}_#{record.id}")
      body = row.at_css("[data-field='excerpt']").text.strip
      expect(body).to include("[...]")
      expect(body.length).to be <= 140
      expect(body).not_to include(long_content)
      expect(row.at_css("[data-field='reference']")).to be_nil
      source_summary = row.at_css("[data-field='metadata']").text.strip
      expect(source_summary).to include("#{source_author.name} : ", "[...]")
      expect(source_summary).not_to include(long_content)
      anchor = record_type == "comment" ? ActionView::RecordIdentifier.dom_id(record) : nil
      target = record_type == "comment" ? source : record
      expect(row.at_css("a[href='#{jjaek_path(target, return_to: content_admin_user_path(reader), anchor: anchor)}']")).to be_present
    end
  end

  it "navigates activity areas and types while preserving filters and using one table" do
    group_admin = User.create!(name: "Filter group admin", email: "filter-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Filter club", group_type: :private_group)
    book = Book.create!(title: "Filter book", authors_text: "Author")
    personal = reader.jjaeks.create!(content: "FILTER_PERSONAL_MATCH")
    group_general = reader.jjaeks.create!(group:, content: "FILTER_GROUP_MATCH")
    book_jjaek = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: reader, content: "FILTER_BOOK_MATCH")
    source = group_admin.jjaeks.create!(content: "FILTER_SOURCE")
    requote = reader.jjaeks.create!(quoted_jjaek: source, content: "FILTER_REQUOTE_MATCH")
    comment = source.comments.create!(user: reader, content: "FILTER_COMMENT_MATCH")
    hidden_jjaek = reader.jjaeks.create!(content: "FILTER_HIDDEN_JJAEK")
    Jjaeks::Hide.new(hidden_jjaek, actor: admin, public_reason: "other").call!
    hidden_comment = source.comments.create!(user: reader, content: "FILTER_HIDDEN_COMMENT")
    Comments::Hide.new(hidden_comment, actor: admin, public_reason: "other").call!
    deleted = reader.jjaeks.create!(content: "FILTER_DELETED_MATCH")
    deleted.comments.create!(user: group_admin, content: "PRESERVE_FILTER_DELETED")
    deleted.destroy_or_tombstone!
    sign_in admin

    get content_admin_user_path(reader)
    document = Nokogiri::HTML(response.body)
    area_navigation = document.at_css("nav[aria-label='영역']")
    type_navigation = document.at_css("nav[aria-label='유형']")
    expect(document.at_css("#admin_user_activity_controls h2").text.strip).to eq("사용자 활동")
    expect(area_navigation.css("a").map { |link| link.text.strip }).to eq(
      [ "전체", "개인", "동아리" ]
    )
    expect(type_navigation.css("a").map { |link| link.text.strip }).to eq(
      [ "전체", "짹", "동아리짹", "다시짹", "댓글" ]
    )
    expect(area_navigation.at_css("a[aria-current='page']").text.strip).to eq("전체")
    expect(type_navigation.at_css("a[aria-current='page']").text.strip).to eq("전체")
    expect(document.at_css("select[name='kind']")).to be_nil
    expect(document.at_css("input[name='q']")).to be_present
    expect(document.at_css("select[name='location']")).to be_nil
    expect(document.at_css("input[type='hidden'][name='location']")).to be_nil
    expect(document.at_css("input[type='hidden'][name='content']")).to be_present
    expect(document.at_css("select[name='status']")).to be_present
    expect(document.css("select[name='status'] option").map { |option| option.text.strip }).to eq(
      [ "전체", "정상", "숨김", "삭제됨" ]
    )
    expect(document.at_css("select[name='sort']")).to be_present

    {
      { q: "personal_match" } => [ personal ],
      { content: "general" } => [ personal, book_jjaek, hidden_jjaek, deleted ],
      { content: "group" } => [ group_general ],
      { content: "requote", q: "REQUOTE" } => [ requote ],
      { content: "comments" } => [ comment, hidden_comment ],
      { location: "personal" } => [ personal, book_jjaek, requote, comment, hidden_jjaek, hidden_comment, deleted ],
      { location: "group" } => [ group_general ],
      { status: "active" } => [ personal, group_general, book_jjaek, requote, comment ],
      { status: "hidden" } => [ hidden_jjaek, hidden_comment ],
      { status: "deleted" } => [ deleted ],
      { q: "group_match", content: "group", location: "group", status: "active" } => [ group_general ]
    }.each do |filters, expected_records|
      get content_admin_user_path(reader), params: filters
      filtered_document = Nokogiri::HTML(response.body)
      rows = filtered_document.css("#admin_user_content_timeline tbody tr")
      expected_ids = expected_records.map do |record|
        record_type = record.is_a?(Comment) ? "comment" : "jjaek"
        "timeline_#{record_type}_#{record.id}"
      end
      expect(rows.map { |row| row["id"] }).to match_array(expected_ids)
      expect(filtered_document.css("#admin_user_content_timeline th").map { |header| header.text.strip }).to eq(
        [ "유형", "영역", "본문", "상태", "작성 시각", "작업" ]
      )
    end

    get content_admin_user_path(reader), params: {
      content: "invalid",
      location: "invalid",
      status: "invalid",
      sort: "invalid",
      all_page: "invalid"
    }
    expect(response).to have_http_status(:ok)
    invalid_document = Nokogiri::HTML(response.body)
    expect(invalid_document.css("#admin_user_content_timeline tbody tr").size).to eq(8)
    expect(invalid_document.at_css("nav[aria-label='영역'] a[aria-current='page']").text.strip).to eq("전체")
    expect(invalid_document.at_css("nav[aria-label='유형'] a[aria-current='page']").text.strip).to eq("전체")

    get content_admin_user_path(reader), params: {
      content: "comments",
      q: "FILTER",
      location: "group",
      status: "active",
      sort: "oldest",
      all_page: 3
    }
    filtered_document = Nokogiri::HTML(response.body)
    expect(filtered_document.at_css("input[name='content']")["value"]).to eq("comments")
    expect(filtered_document.at_css("input[type='hidden'][name='location']")["value"]).to eq("group")
    expect(filtered_document.at_css("nav[aria-label='영역'] a[aria-current='page']").text.strip).to eq("동아리")
    expect(filtered_document.at_css("nav[aria-label='유형'] a[aria-current='page']").text.strip).to eq("댓글")
    reset_link = filtered_document.css("a").find { |link| link.text.strip == "조건 초기화" }
    expect(reset_link["href"]).to eq(content_admin_user_path(reader, content: "comments", location: "group"))
    group_link = filtered_document.css("nav[aria-label='유형'] a").find { |link| link.text.strip == "동아리짹" }
    expect(group_link["href"]).to include(
      "content=group", "q=FILTER", "location=group", "status=active", "sort=oldest"
    )
    expect(group_link["href"]).not_to include("all_page")
    personal_link = filtered_document.css("nav[aria-label='영역'] a").find { |link| link.text.strip == "개인" }
    expect(personal_link["href"]).to include(
      "content=comments", "location=personal", "q=FILTER", "status=active", "sort=oldest"
    )
    expect(personal_link["href"]).not_to include("all_page")
    all_areas_link = filtered_document.css("nav[aria-label='영역'] a").find { |link| link.text.strip == "전체" }
    expect(all_areas_link["href"]).to include("content=comments", "q=FILTER", "status=active", "sort=oldest")
    expect(all_areas_link["href"]).not_to include("location=", "all_page")
  end

  it "combines personal and Group activity areas with types and keeps the selected axes on reset" do
    group_admin = User.create!(name: "Area group admin", email: "area-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Area club", group_type: :private_group)
    GroupMembership.create!(group:, user: reader, status: :active)
    book = Book.create!(title: "Area book", authors_text: "Author")
    personal_general = reader.jjaeks.create!(content: "COMBO_PERSONAL_GENERAL")
    personal_book = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: reader, content: "COMBO_PERSONAL_BOOK")
    group_general = reader.jjaeks.create!(group:, content: "COMBO_GROUP_GENERAL")
    group_book = create_jjaek_with_books(legacy_source_kind: "book", books: [ book ], user: reader, group:, content: "COMBO_GROUP_BOOK")
    group_source = group_admin.jjaeks.create!(group:, content: "COMBO_GROUP_SOURCE")
    group_comment = group_source.comments.create!(user: reader, content: "COMBO_GROUP_COMMENT")
    sign_in admin

    {
      { location: "group", content: "group" } => [ group_general, group_book ],
      { location: "personal", content: "general" } => [ personal_general, personal_book ],
      { location: "group", content: "comments" } => [ group_comment ]
    }.each do |filters, expected_records|
      get content_admin_user_path(reader), params: filters.merge(q: "COMBO", status: "active", sort: "oldest")
      document = Nokogiri::HTML(response.body)
      expected_ids = expected_records.map do |record|
        record_type = record.is_a?(Comment) ? "comment" : "jjaek"
        "timeline_#{record_type}_#{record.id}"
      end
      expect(document.css("#admin_user_content_timeline tbody tr").map { |row| row["id"] }).to eq(expected_ids)
      expect(document.at_css("input[name='location']")["value"]).to eq(filters[:location])
      expect(document.at_css("input[name='content']")["value"]).to eq(filters[:content])
      expect(document.at_css("input[name='q']")["value"]).to eq("COMBO")
      expect(document.at_css("select[name='status'] option[selected]")["value"]).to eq("active")
      expect(document.at_css("select[name='sort'] option[selected]")["value"]).to eq("oldest")
      reset_link = document.css("a").find { |link| link.text.strip == "조건 초기화" }
      expect(reset_link["href"]).to eq(
        content_admin_user_path(reader, content: filters[:content], location: filters[:location])
      )
    end
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

    get content_admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "recent" }
    first_page = Nokogiri::HTML(response.body)
    first_page_rows = first_page.css("#admin_user_content_timeline tbody tr")
    expect(first_page_rows.size).to eq(30)
    expect(first_page_rows.first(4).map(&:text).join).to match(
      /PAGED_GENERAL_0.*PAGED_COMMENT_0.*PAGED_GENERAL_1.*PAGED_COMMENT_1/m
    )
    expect(response.body).to include("content=all", "q=PAGED", "sort=recent", "all_page=2")

    get content_admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "recent", all_page: 2 }
    second_page = Nokogiri::HTML(response.body)
    expect(second_page.css("#admin_user_content_timeline tbody tr").size).to eq(21)
    expect(second_page.css("#admin_user_content_timeline tbody tr").first.text).to include("PAGED_GENERAL_15")
    expect(second_page.css("#admin_user_content_timeline tbody tr").last.text).to include("PAGED_GENERAL_25")

    get content_admin_user_path(reader), params: { content: "all", q: "PAGED", sort: "oldest" }
    oldest_first = Nokogiri::HTML(response.body).css("#admin_user_content_timeline tbody tr").first
    expect(oldest_first.text).to include("PAGED_GENERAL_25")
  end
end
