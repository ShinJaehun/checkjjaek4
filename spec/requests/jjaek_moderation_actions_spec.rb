require "rails_helper"

RSpec.describe "Jjaek moderation actions", type: :request do
  let!(:author) { User.create!(name: "Author", email: "jjaek-action-author@example.com", password: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "jjaek-action-member@example.com", password: "password123!") }
  let!(:group_admin) { User.create!(name: "Group admin", email: "jjaek-action-group-admin@example.com", password: "password123!") }
  let!(:other_group_admin) { User.create!(name: "Other group admin", email: "jjaek-action-other-admin@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Platform admin", email: "jjaek-action-admin@example.com", password: "password123!", global_admin: true) }
  let!(:other_admin) { User.create!(name: "Other platform admin", email: "jjaek-action-other-platform@example.com", password: "password123!", global_admin: true) }
  let!(:book) { Book.create!(title: "Action book", authors_text: "Book author") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Action group", group_type: :private_group) }

  before do
    group.group_memberships.create!(user: author, status: :active)
    group.group_memberships.create!(user: member, status: :active)
  end

  def create_hide!(jjaek, actor:, authority:, public_reason: "other", internal_note: nil)
    jjaek.update!(hidden_at: Time.current)
    ModerationAction.create!(
      target: jjaek,
      actor:,
      action_type: :hide,
      public_reason:,
      internal_note:,
      moderation_authority: authority
    )
  end

  def expect_stale_jjaek_action(new_path:, create_path:, jjaek_id:)
    jjaek_count = Jjaek.count
    moderation_action_count = ModerationAction.count
    notification_count = Notification.count
    allow(Notifications::ModerationNotifier).to receive(:schedule)

    get new_path
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))

    post create_path, params: { moderation_action: { public_reason: "Stale action" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
    expect(Jjaek.count).to eq(jjaek_count)
    expect(Jjaek.exists?(jjaek_id)).to be(false)
    expect(ModerationAction.count).to eq(moderation_action_count)
    expect(Notification.count).to eq(notification_count)
    expect(Notifications::ModerationNotifier).not_to have_received(:schedule)
  end

  it "uses platform Action pages for hide and restore while preserving audit and notification semantics" do
    jjaek = author.jjaeks.create!(group:, book:, content: "PLATFORM ACTION TARGET")
    sign_in admin
    hide_new_path = new_admin_jjaek_hide_path(jjaek)
    hide_create_path = admin_jjaek_hides_path(jjaek)

    get jjaek_path(jjaek)
    detail = Nokogiri::HTML(response.body)
    action = detail.at_css("[data-jjaek-moderation-action]")
    expect(action["href"]).to eq(hide_new_path)
    expect(action.text.strip).to eq("숨김")
    expect(detail.at_css("#admin_moderation_history_section")).to be_nil
    expect(detail.text).not_to include("콘텐츠 관리", "현재 상태")

    get hide_new_path
    page = Nokogiri::HTML(response.body)
    context = page.at_css("[data-jjaek-moderation-context]")
    expect(context.text).to include(
      author.name,
      group.name,
      book.title,
      "PLATFORM ACTION TARGET",
      I18n.l(jjaek.created_at, format: :short)
    )
    reason_select = page.at_css("form[action='#{hide_create_path}'] select[name='moderation_action[public_reason]']")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*Jjaek::MODERATION_HIDE_REASONS)
    expect(page.at_css("textarea[name='moderation_action[internal_note]']")).to be_present
    expect(page.at_css("a[href='#{jjaek_path(jjaek)}']")).to be_present

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    expect {
      post hide_create_path, params: {
        moderation_action: { public_reason: "personal_information", internal_note: "Platform hide note" }
      }
    }.to change(ModerationAction, :count).by(1)

    hide = jjaek.current_hide_action
    expect(jjaek.reload).to be_hidden
    expect(hide).to have_attributes(
      actor: admin,
      action_type: "hide",
      public_reason: "personal_information",
      internal_note: "Platform hide note",
      moderation_authority: "platform"
    )
    expect(scheduled.last).to eq([ hide, [ author.id ] ])
    expect(response).to redirect_to(jjaek_path(jjaek))

    restore_new_path = new_admin_jjaek_restoration_path(jjaek)
    restore_create_path = admin_jjaek_restorations_path(jjaek)
    get restore_new_path
    page = Nokogiri::HTML(response.body)
    current_hide = page.at_css("[data-current-hide-action-id='#{hide.id}']")
    expect(current_hide).to be_present
    expect(current_hide.text).to include(
      "숨김",
      "시스템 관리자",
      admin.name,
      I18n.l(hide.created_at, format: :short),
      "개인정보 노출",
      "Platform hide note"
    )
    expect(current_hide.at_css("[data-moderation-detail='reason']")).to be_present
    expect(current_hide.at_css("[data-role='internal-note'][data-moderation-detail='memo']")).to be_present
    expect(page.at_css("form[action='#{restore_create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present

    expect {
      post restore_create_path, params: {
        moderation_action: { public_reason: "Reviewed and restored", internal_note: "Platform restore note" }
      }
    }.to change(ModerationAction, :count).by(1)

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(jjaek.reload).not_to be_hidden
    expect(restoration).to have_attributes(
      actor: admin,
      action_type: "restore",
      public_reason: "Reviewed and restored",
      internal_note: "Platform restore note",
      moderation_authority: "platform"
    )
    expect(scheduled.last).to eq([ restoration, [ author.id ] ])
    expect(response).to redirect_to(jjaek_path(jjaek))
  end

  it "safely redirects stale platform hide pages and submissions" do
    jjaek = author.jjaeks.create!(content: "STALE PLATFORM HIDE TARGET")
    jjaek_id = jjaek.id
    new_path = new_admin_jjaek_hide_path(jjaek)
    create_path = admin_jjaek_hides_path(jjaek)
    jjaek.destroy_or_tombstone!
    sign_in admin

    expect_stale_jjaek_action(new_path:, create_path:, jjaek_id:)
  end

  it "safely redirects stale platform restoration pages and submissions" do
    jjaek = author.jjaeks.create!(content: "STALE PLATFORM RESTORE TARGET")
    hide = create_hide!(jjaek, actor: admin, authority: "platform")
    jjaek_id = jjaek.id
    new_path = new_admin_jjaek_restoration_path(jjaek)
    create_path = admin_jjaek_restorations_path(jjaek)
    jjaek.destroy_or_tombstone!
    sign_in admin

    expect_stale_jjaek_action(new_path:, create_path:, jjaek_id:)
    expect(hide.reload).to be_persisted
    expect(ModerationAction.where(reversal_of: hide)).to be_empty
  end

  it "uses Group Action pages for hide and restore with group authority" do
    jjaek = author.jjaeks.create!(group:, book:, content: "GROUP ACTION TARGET")
    sign_in group_admin
    hide_new_path = new_jjaek_group_hide_path(jjaek)
    hide_create_path = jjaek_group_hides_path(jjaek)

    get jjaek_path(jjaek)
    detail = Nokogiri::HTML(response.body)
    action = detail.at_css("[data-jjaek-moderation-action]")
    expect(action["href"]).to eq(hide_new_path)
    expect(action.text.strip).to eq("숨김")
    expect(detail.at_css("#group_moderation_history")).to be_nil
    expect(detail.text).not_to include("콘텐츠 관리", "현재 상태")

    get hide_new_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-jjaek-moderation-context]").text).to include(
      author.name,
      group.name,
      book.title,
      "GROUP ACTION TARGET"
    )
    reason_select = page.at_css("form[action='#{hide_create_path}'] select[name='moderation_action[public_reason]']")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*Jjaek::MODERATION_HIDE_REASONS)
    expect(page.text).to include("선택 입력 · 동아리 운영자에게만 표시됩니다.")

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    post hide_create_path, params: {
      moderation_action: { public_reason: "other", internal_note: "Group hide note" }
    }

    hide = jjaek.current_hide_action
    expect(jjaek.reload).to be_hidden
    expect(hide).to have_attributes(
      actor: group_admin,
      action_type: "hide",
      public_reason: "other",
      internal_note: "Group hide note",
      moderation_authority: "group"
    )
    expect(scheduled.last).to eq([ hide, [ author.id ] ])

    restore_new_path = new_jjaek_group_restoration_path(jjaek)
    restore_create_path = jjaek_group_restorations_path(jjaek)
    get restore_new_path
    page = Nokogiri::HTML(response.body)
    current_hide = page.at_css("[data-current-hide-action-id='#{hide.id}']")
    expect(current_hide.text).to include(
      "숨김",
      "동아리 관리자",
      group_admin.name,
      "기타",
      "Group hide note"
    )
    expect(current_hide.at_css("[data-moderation-detail='reason']")).to be_present
    expect(current_hide.at_css("[data-role='internal-note'][data-moderation-detail='memo']")).to be_present
    expect(page.at_css("form[action='#{restore_create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present

    post restore_create_path, params: {
      moderation_action: { public_reason: "Group review complete", internal_note: "Group restore note" }
    }

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(jjaek.reload).not_to be_hidden
    expect(restoration).to have_attributes(
      actor: group_admin,
      action_type: "restore",
      public_reason: "Group review complete",
      internal_note: "Group restore note",
      moderation_authority: "group"
    )
    expect(scheduled.last).to eq([ restoration, [ author.id ] ])
    expect(response).to redirect_to(jjaek_path(jjaek))
  end

  it "safely redirects stale Group hide pages and submissions" do
    jjaek = author.jjaeks.create!(group:, content: "STALE GROUP HIDE TARGET")
    jjaek_id = jjaek.id
    new_path = new_jjaek_group_hide_path(jjaek)
    create_path = jjaek_group_hides_path(jjaek)
    jjaek.destroy_or_tombstone!
    sign_in group_admin

    expect_stale_jjaek_action(new_path:, create_path:, jjaek_id:)
  end

  it "safely redirects stale Group restoration pages and submissions" do
    jjaek = author.jjaeks.create!(group:, content: "STALE GROUP RESTORE TARGET")
    hide = create_hide!(jjaek, actor: group_admin, authority: "group")
    jjaek_id = jjaek.id
    new_path = new_jjaek_group_restoration_path(jjaek)
    create_path = jjaek_group_restorations_path(jjaek)
    jjaek.destroy_or_tombstone!
    sign_in group_admin

    expect_stale_jjaek_action(new_path:, create_path:, jjaek_id:)
    expect(hide.reload).to be_persisted
    expect(ModerationAction.where(reversal_of: hide)).to be_empty
  end

  it "uses the same generic response for missing and inaccessible Jjaeks" do
    missing = author.jjaeks.create!(group:, content: "MISSING RESPONSE TARGET")
    missing_path = new_jjaek_group_hide_path(missing)
    missing_create_path = jjaek_group_hides_path(missing)
    missing.destroy_or_tombstone!

    inaccessible_admin = User.create!(
      name: "Inaccessible group admin",
      email: "jjaek-action-inaccessible-admin@example.com",
      password: "password123!"
    )
    inaccessible_group = Group.create!(
      lifecycle_status: :active,
      group_admin: inaccessible_admin,
      name: "Inaccessible action group",
      group_type: :private_group
    )
    inaccessible = author.jjaeks.create!(group: inaccessible_group, content: "INACCESSIBLE ACTION TARGET")
    sign_in group_admin

    get missing_path
    missing_response = [ response.status, response.location, flash[:alert] ]

    get new_jjaek_group_hide_path(inaccessible)
    expect([ response.status, response.location, flash[:alert] ]).to eq(missing_response)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))

    moderation_action_count = ModerationAction.count
    notification_count = Notification.count
    allow(Notifications::ModerationNotifier).to receive(:schedule)

    post missing_create_path, params: { moderation_action: { public_reason: "Missing" } }
    missing_create_response = [ response.status, response.location, flash[:alert] ]

    post jjaek_group_hides_path(inaccessible), params: { moderation_action: { public_reason: "Inaccessible" } }
    expect([ response.status, response.location, flash[:alert] ]).to eq(missing_create_response)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("jjaeks.alerts.not_found_or_inaccessible"))
    expect(inaccessible.reload).not_to be_hidden
    expect(ModerationAction.count).to eq(moderation_action_count)
    expect(Notification.count).to eq(notification_count)
    expect(Notifications::ModerationNotifier).not_to have_received(:schedule)
  end

  it "keeps existing Pundit authorization for visible Jjaeks without moderation permission" do
    jjaek = author.jjaeks.create!(group:, content: "VISIBLE BUT NOT MODERATABLE")
    sign_in member

    get new_jjaek_group_hide_path(jjaek)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))

    expect {
      post jjaek_group_hides_path(jjaek), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
    expect(jjaek.reload).not_to be_hidden
  end

  it "lets platform authority restore a group-origin hide without changing the hide snapshot" do
    jjaek = author.jjaeks.create!(group:, content: "PLATFORM OVERRIDE TARGET")
    hide = create_hide!(jjaek, actor: group_admin, authority: "group", internal_note: "Group-only note")
    sign_in admin

    get new_admin_jjaek_restoration_path(jjaek)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("동아리 관리자", "Group-only note")

    post admin_jjaek_restorations_path(jjaek), params: {
      moderation_action: { public_reason: "Platform override" }
    }

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(jjaek.reload).not_to be_hidden
    expect(hide.reload).to be_group_authority
    expect(restoration).to have_attributes(moderation_authority: "platform", public_reason: "Platform override")
  end

  it "denies platform Action pages and mutations to ordinary users and the Jjaek author" do
    visible = author.jjaeks.create!(content: "PLATFORM DENIED VISIBLE")
    hidden = author.jjaeks.create!(content: "PLATFORM DENIED HIDDEN")
    create_hide!(hidden, actor: admin, authority: "platform")

    sign_in member
    get new_admin_jjaek_hide_path(visible)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_hides_path(visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_admin_jjaek_restoration_path(hidden)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_restorations_path(hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    own_visible = admin.jjaeks.create!(content: "PLATFORM SELF VISIBLE")
    own_hidden = admin.jjaeks.create!(content: "PLATFORM SELF HIDDEN")
    create_hide!(own_hidden, actor: other_admin, authority: "platform")
    sign_in admin
    get new_admin_jjaek_hide_path(own_visible)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_hides_path(own_visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_admin_jjaek_restoration_path(own_hidden)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_restorations_path(own_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    expect(visible.reload).not_to be_hidden
    expect(hidden.reload).to be_hidden
    expect(own_visible.reload).not_to be_hidden
    expect(own_hidden.reload).to be_hidden
  end

  it "denies platform hide and restore for deleted Jjaeks" do
    deleted = author.jjaeks.create!(content: "DELETED PLATFORM TARGET")
    deleted.comments.create!(user: member, content: "Preserve row")
    deleted.destroy_or_tombstone!
    hidden_deleted = author.jjaeks.create!(content: "HIDDEN DELETED PLATFORM TARGET")
    hidden_deleted.comments.create!(user: member, content: "Preserve hidden row")
    create_hide!(hidden_deleted, actor: admin, authority: "platform")
    hidden_deleted.destroy_or_tombstone!
    sign_in admin

    get new_admin_jjaek_hide_path(deleted)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
    post admin_jjaek_hides_path(deleted), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
    get new_admin_jjaek_restoration_path(hidden_deleted)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
    post admin_jjaek_restorations_path(hidden_deleted), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("auth.alerts.not_authorized"))
  end

  it "keeps Group Action URLs inside the existing actor, author, and authority boundaries" do
    other_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Other action group", group_type: :private_group)
    other_group.group_memberships.create!(user: author, status: :active)
    visible = author.jjaeks.create!(group:, content: "GROUP DENIED VISIBLE")
    hidden = author.jjaeks.create!(group:, content: "GROUP DENIED HIDDEN")
    create_hide!(hidden, actor: group_admin, authority: "group")

    [ member, other_group_admin, admin ].each do |actor|
      sign_in actor
      get new_jjaek_group_hide_path(visible)
      expect(response).to redirect_to(root_path)
      post jjaek_group_hides_path(visible), params: { moderation_action: { public_reason: "other" } }
      expect(response).to redirect_to(root_path)
      get new_jjaek_group_restoration_path(hidden)
      expect(response).to redirect_to(root_path)
      post jjaek_group_restorations_path(hidden), params: { moderation_action: { public_reason: "Blocked" } }
      expect(response).to redirect_to(root_path)
    end

    own_visible = group_admin.jjaeks.create!(group:, content: "GROUP SELF VISIBLE")
    own_hidden = group_admin.jjaeks.create!(group:, content: "GROUP SELF HIDDEN")
    create_hide!(own_hidden, actor: other_group_admin, authority: "group")
    global_authored = admin.jjaeks.create!(group:, content: "GLOBAL AUTHORED GROUP TARGET")
    sign_in group_admin

    [ own_visible, global_authored ].each do |target|
      get new_jjaek_group_hide_path(target)
      expect(response).to redirect_to(root_path)
      post jjaek_group_hides_path(target), params: { moderation_action: { public_reason: "other" } }
      expect(response).to redirect_to(root_path)
    end
    get new_jjaek_group_restoration_path(own_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_group_restorations_path(own_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    group_admin.update!(global_admin: true)
    get new_jjaek_group_hide_path(visible)
    expect(response).to redirect_to(root_path)
    post jjaek_group_hides_path(visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_group_restoration_path(hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_group_restorations_path(hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
  end

  it "does not let Group authority restore a platform-origin hide" do
    jjaek = author.jjaeks.create!(group:, content: "PLATFORM HIDE GROUP TARGET")
    hide = create_hide!(jjaek, actor: admin, authority: "platform", internal_note: "Platform-only note")
    sign_in group_admin

    get new_jjaek_group_restoration_path(jjaek)
    expect(response).to redirect_to(root_path)
    post jjaek_group_restorations_path(jjaek), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
    expect(jjaek.reload).to be_hidden
    expect(ModerationAction.where(reversal_of: hide)).to be_empty
  end

  it "preserves inactive restoration and operation-suspension boundaries for Group actions" do
    hidden_before_closure = author.jjaeks.create!(group:, content: "HIDDEN BEFORE CLOSURE")
    hide = create_hide!(hidden_before_closure, actor: group_admin, authority: "group")
    inactive_target = author.jjaeks.create!(group:, content: "INACTIVE HIDE TARGET")
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    sign_in group_admin

    get new_jjaek_group_hide_path(inactive_target)
    expect(response).to redirect_to(root_path)
    post jjaek_group_hides_path(inactive_target), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_group_restoration_path(hidden_before_closure)
    expect(response).to have_http_status(:ok)
    post jjaek_group_restorations_path(hidden_before_closure), params: { moderation_action: { public_reason: "Resolved" } }
    expect(response).to redirect_to(jjaek_path(hidden_before_closure))
    expect(ModerationAction.find_by!(reversal_of: hide)).to be_group_authority

    suspended_group = Group.create!(
      lifecycle_status: :active,
      group_admin:,
      name: "Suspended action group",
      group_type: :private_group
    )
    suspended_group.group_memberships.create!(user: author, status: :active)
    suspended_visible = author.jjaeks.create!(group: suspended_group, content: "SUSPENDED GROUP HIDE TARGET")
    suspended_hidden = author.jjaeks.create!(group: suspended_group, content: "SUSPENDED GROUP RESTORE TARGET")
    create_hide!(suspended_hidden, actor: group_admin, authority: "group")
    suspended_group.update!(operation_suspended_at: Time.current)

    get new_jjaek_group_hide_path(suspended_visible)
    expect(response).to redirect_to(root_path)
    post jjaek_group_hides_path(suspended_visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_group_restoration_path(suspended_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_group_restorations_path(suspended_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
  end

  it "renders platform Action pages with context and entered values when services fail" do
    jjaek = author.jjaeks.create!(book:, content: "PLATFORM FAILURE CONTEXT")
    sign_in admin
    hide_service = instance_double(Jjaeks::Hide)
    allow(Jjaeks::Hide).to receive(:new).and_return(hide_service)
    allow(hide_service).to receive(:call!).and_raise(Jjaeks::Hide::InvalidState)

    post admin_jjaek_hides_path(jjaek), params: {
      moderation_action: { public_reason: "other", internal_note: "Keep platform hide note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-jjaek-moderation-context]").text).to include(author.name, book.title, "PLATFORM FAILURE CONTEXT")
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep platform hide note")
    expect(jjaek.reload).not_to be_hidden

    hide = create_hide!(jjaek, actor: admin, authority: "platform", internal_note: "Current platform hide")
    restore_service = instance_double(Jjaeks::Restore)
    allow(Jjaeks::Restore).to receive(:new).and_return(restore_service)
    allow(restore_service).to receive(:call!).and_raise(Jjaeks::Restore::InvalidState)

    post admin_jjaek_restorations_path(jjaek), params: {
      moderation_action: { public_reason: "Retry platform restore", internal_note: "Keep platform restore note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-current-hide-action-id='#{hide.id}']").text).to include("Current platform hide")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry platform restore")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep platform restore note")
    expect(jjaek.reload).to be_hidden
  end

  it "renders Group Action pages with context and entered values when services fail" do
    jjaek = author.jjaeks.create!(group:, content: "GROUP FAILURE CONTEXT")
    sign_in group_admin
    hide_service = instance_double(Jjaeks::Hide)
    allow(Jjaeks::Hide).to receive(:new).and_return(hide_service)
    allow(hide_service).to receive(:call!).and_raise(Jjaeks::Hide::InvalidState)

    post jjaek_group_hides_path(jjaek), params: {
      moderation_action: { public_reason: "other", internal_note: "Keep group hide note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-jjaek-moderation-context]").text).to include(author.name, group.name, "GROUP FAILURE CONTEXT")
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep group hide note")
    expect(jjaek.reload).not_to be_hidden

    hide = create_hide!(jjaek, actor: group_admin, authority: "group", internal_note: "Current group hide")
    restore_service = instance_double(Jjaeks::Restore)
    allow(Jjaeks::Restore).to receive(:new).and_return(restore_service)
    allow(restore_service).to receive(:call!).and_raise(Jjaeks::Restore::InvalidState)

    post jjaek_group_restorations_path(jjaek), params: {
      moderation_action: { public_reason: "Retry group restore", internal_note: "Keep group restore note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-current-hide-action-id='#{hide.id}']").text).to include("Current group hide")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry group restore")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep group restore note")
    expect(jjaek.reload).to be_hidden
  end

  it "does not recognize the four removed legacy PATCH routes" do
    jjaek = author.jjaeks.create!(content: "LEGACY ROUTE TARGET")

    expect {
      Rails.application.routes.recognize_path("/admin/jjaeks/#{jjaek.id}/hide", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/admin/jjaeks/#{jjaek.id}/restore", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/jjaeks/#{jjaek.id}/hide", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/jjaeks/#{jjaek.id}/restore", method: :patch)
    }.to raise_error(ActionController::RoutingError)
  end
end
