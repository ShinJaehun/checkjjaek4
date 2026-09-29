require "rails_helper"

RSpec.describe "Comment moderation actions", type: :request do
  let!(:parent_author) { User.create!(name: "Parent author", email: "comment-action-parent@example.com", password: "password123!") }
  let!(:comment_author) { User.create!(name: "Comment author", email: "comment-action-author@example.com", password: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "comment-action-member@example.com", password: "password123!") }
  let!(:group_admin) { User.create!(name: "Group admin", email: "comment-action-group-admin@example.com", password: "password123!") }
  let!(:other_group_admin) { User.create!(name: "Other group admin", email: "comment-action-other-admin@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Platform admin", email: "comment-action-admin@example.com", password: "password123!", global_admin: true) }
  let!(:other_admin) { User.create!(name: "Other platform admin", email: "comment-action-other-platform@example.com", password: "password123!", global_admin: true) }
  let!(:book) { Book.create!(title: "Comment action book", authors_text: "Book author") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Comment action group", group_type: :private_group) }
  let!(:jjaek) { parent_author.jjaeks.create!(group:, book:, content: "COMMENT ACTION PARENT") }
  let!(:comment) { jjaek.comments.create!(user: comment_author, content: "COMMENT ACTION TARGET") }

  before do
    group.group_memberships.create!(user: parent_author, status: :active)
    group.group_memberships.create!(user: comment_author, status: :active)
    group.group_memberships.create!(user: member, status: :active)
  end

  def create_hide!(target, actor:, authority:, public_reason: "other", internal_note: nil)
    target.update!(hidden_at: Time.current)
    ModerationAction.create!(
      target:,
      actor:,
      action_type: :hide,
      public_reason:,
      internal_note:,
      moderation_authority: authority
    )
  end

  def anchored_jjaek_path(target)
    jjaek_path(target.jjaek, anchor: ActionView::RecordIdentifier.dom_id(target))
  end

  it "uses platform Action pages for hide and restore while preserving audit and notification semantics" do
    sign_in admin
    hide_new_path = new_admin_jjaek_comment_hide_path(jjaek, comment)
    hide_create_path = admin_jjaek_comment_hides_path(jjaek, comment)

    get jjaek_path(jjaek)
    card = Nokogiri::HTML(response.body).at_css("#comment_#{comment.id}")
    expect(card.at_css("[data-comment-moderation-state] a[href='#{hide_new_path}']").text.strip).to eq("숨김")
    expect(card.at_css("[data-comment-moderation-state] form")).to be_nil

    get hide_new_path
    page = Nokogiri::HTML(response.body)
    context = page.at_css("[data-comment-moderation-context]")
    expect(context.text.squish).to include(
      comment_author.name,
      "COMMENT ACTION TARGET",
      I18n.l(comment.created_at, format: :short),
      parent_author.name,
      group.name,
      book.title,
      "COMMENT ACTION PARENT",
      "부모 상태: 공개"
    )
    reason_select = page.at_css("form[action='#{hide_create_path}'] select[name='moderation_action[public_reason]']")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*Comment::MODERATION_HIDE_REASONS)
    expect(page.at_css("textarea[name='moderation_action[internal_note]']")).to be_present
    expect(page.at_css("a[href='#{anchored_jjaek_path(comment)}']")).to be_present

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    expect {
      post hide_create_path, params: {
        moderation_action: { public_reason: "personal_information", internal_note: "Platform comment hide note" }
      }
    }.to change(ModerationAction, :count).by(1)

    hide = comment.current_hide_action
    expect(comment.reload).to be_hidden
    expect(hide).to have_attributes(
      actor: admin,
      action_type: "hide",
      public_reason: "personal_information",
      internal_note: "Platform comment hide note",
      moderation_authority: "platform"
    )
    expect(scheduled.last).to eq([ hide, [ comment_author.id ] ])
    expect(response).to redirect_to(anchored_jjaek_path(comment))

    restore_new_path = new_admin_jjaek_comment_restoration_path(jjaek, comment)
    restore_create_path = admin_jjaek_comment_restorations_path(jjaek, comment)
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
      "Platform comment hide note"
    )
    expect(current_hide.at_css("[data-moderation-detail='reason']")).to be_present
    expect(current_hide.at_css("[data-role='internal-note'][data-moderation-detail='memo']")).to be_present
    expect(page.at_css("form[action='#{restore_create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present

    expect {
      post restore_create_path, params: {
        moderation_action: { public_reason: "Reviewed and restored", internal_note: "Platform comment restore note" }
      }
    }.to change(ModerationAction, :count).by(1)

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(comment.reload).not_to be_hidden
    expect(restoration).to have_attributes(
      actor: admin,
      action_type: "restore",
      public_reason: "Reviewed and restored",
      internal_note: "Platform comment restore note",
      moderation_authority: "platform"
    )
    expect(scheduled.last).to eq([ restoration, [ comment_author.id ] ])
    expect(response).to redirect_to(anchored_jjaek_path(comment))
  end

  it "uses Group Action pages for hide and restore with group authority" do
    sign_in group_admin
    hide_new_path = new_jjaek_comment_group_hide_path(jjaek, comment)
    hide_create_path = jjaek_comment_group_hides_path(jjaek, comment)

    get jjaek_path(jjaek)
    card = Nokogiri::HTML(response.body).at_css("#comment_#{comment.id}")
    expect(card.at_css("[data-comment-moderation-state] a[href='#{hide_new_path}']").text.strip).to eq("숨김")
    expect(card.at_css("[data-comment-moderation-state] form")).to be_nil

    get hide_new_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-comment-moderation-context]").text).to include(
      comment_author.name,
      "COMMENT ACTION TARGET",
      parent_author.name,
      group.name,
      book.title,
      "COMMENT ACTION PARENT"
    )
    reason_select = page.at_css("form[action='#{hide_create_path}'] select[name='moderation_action[public_reason]']")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*Comment::MODERATION_HIDE_REASONS)
    expect(page.text).to include("선택 입력 · 동아리 운영자에게만 표시됩니다.")

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    post hide_create_path, params: {
      moderation_action: { public_reason: "other", internal_note: "Group comment hide note" }
    }

    hide = comment.current_hide_action
    expect(comment.reload).to be_hidden
    expect(hide).to have_attributes(
      actor: group_admin,
      action_type: "hide",
      public_reason: "other",
      internal_note: "Group comment hide note",
      moderation_authority: "group"
    )
    expect(scheduled.last).to eq([ hide, [ comment_author.id ] ])

    restore_new_path = new_jjaek_comment_group_restoration_path(jjaek, comment)
    restore_create_path = jjaek_comment_group_restorations_path(jjaek, comment)
    get restore_new_path
    page = Nokogiri::HTML(response.body)
    current_hide = page.at_css("[data-current-hide-action-id='#{hide.id}']")
    expect(current_hide.text).to include("숨김", "동아리 관리자", group_admin.name, "기타", "Group comment hide note")
    expect(current_hide.at_css("[data-moderation-detail='reason']")).to be_present
    expect(current_hide.at_css("[data-role='internal-note'][data-moderation-detail='memo']")).to be_present
    expect(page.at_css("form[action='#{restore_create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present

    post restore_create_path, params: {
      moderation_action: { public_reason: "Group review complete", internal_note: "Group comment restore note" }
    }

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(comment.reload).not_to be_hidden
    expect(restoration).to have_attributes(
      actor: group_admin,
      action_type: "restore",
      public_reason: "Group review complete",
      internal_note: "Group comment restore note",
      moderation_authority: "group"
    )
    expect(scheduled.last).to eq([ restoration, [ comment_author.id ] ])
    expect(response).to redirect_to(anchored_jjaek_path(comment))
  end

  it "lets platform authority restore a group-origin hide without changing the hide snapshot" do
    hide = create_hide!(comment, actor: group_admin, authority: "group", internal_note: "Group-only comment note")
    sign_in admin

    get new_admin_jjaek_comment_restoration_path(jjaek, comment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("동아리 관리자", "Group-only comment note")

    post admin_jjaek_comment_restorations_path(jjaek, comment), params: {
      moderation_action: { public_reason: "Platform override" }
    }

    restoration = ModerationAction.find_by!(reversal_of: hide)
    expect(comment.reload).not_to be_hidden
    expect(hide.reload).to be_group_authority
    expect(restoration).to have_attributes(moderation_authority: "platform", public_reason: "Platform override")
  end

  it "denies platform Action pages and mutations to ordinary users and the Comment author" do
    hidden = jjaek.comments.create!(user: comment_author, content: "PLATFORM DENIED HIDDEN COMMENT")
    create_hide!(hidden, actor: admin, authority: "platform")

    sign_in member
    get new_admin_jjaek_comment_hide_path(jjaek, comment)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_comment_hides_path(jjaek, comment), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_admin_jjaek_comment_restoration_path(jjaek, hidden)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_comment_restorations_path(jjaek, hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    own_visible = jjaek.comments.create!(user: admin, content: "PLATFORM SELF VISIBLE COMMENT")
    own_hidden = jjaek.comments.create!(user: admin, content: "PLATFORM SELF HIDDEN COMMENT")
    create_hide!(own_hidden, actor: other_admin, authority: "platform")
    sign_in admin
    get new_admin_jjaek_comment_hide_path(jjaek, own_visible)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_comment_hides_path(jjaek, own_visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_admin_jjaek_comment_restoration_path(jjaek, own_hidden)
    expect(response).to redirect_to(root_path)
    post admin_jjaek_comment_restorations_path(jjaek, own_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    expect(comment.reload).not_to be_hidden
    expect(hidden.reload).to be_hidden
    expect(own_visible.reload).not_to be_hidden
    expect(own_hidden.reload).to be_hidden
  end

  it "keeps Group Action URLs inside the existing actor, author, and authority boundaries" do
    other_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Other comment action group", group_type: :private_group)
    other_group.group_memberships.create!(user: comment_author, status: :active)
    group_hidden = jjaek.comments.create!(user: comment_author, content: "GROUP HIDDEN COMMENT")
    create_hide!(group_hidden, actor: group_admin, authority: "group")
    platform_hidden = jjaek.comments.create!(user: comment_author, content: "PLATFORM HIDDEN GROUP COMMENT")
    create_hide!(platform_hidden, actor: admin, authority: "platform", internal_note: "Platform-only comment note")

    [ member, other_group_admin, admin ].each do |actor|
      sign_in actor
      get new_jjaek_comment_group_hide_path(jjaek, comment)
      expect(response).to redirect_to(root_path)
      post jjaek_comment_group_hides_path(jjaek, comment), params: { moderation_action: { public_reason: "other" } }
      expect(response).to redirect_to(root_path)
      get new_jjaek_comment_group_restoration_path(jjaek, group_hidden)
      expect(response).to redirect_to(root_path)
      post jjaek_comment_group_restorations_path(jjaek, group_hidden), params: { moderation_action: { public_reason: "Blocked" } }
      expect(response).to redirect_to(root_path)
    end

    own = jjaek.comments.create!(user: group_admin, content: "GROUP SELF COMMENT")
    own_hidden = jjaek.comments.create!(user: group_admin, content: "GROUP SELF HIDDEN COMMENT")
    create_hide!(own_hidden, actor: other_group_admin, authority: "group")
    global_authored = jjaek.comments.create!(user: admin, content: "GLOBAL AUTHORED COMMENT")
    sign_in group_admin
    [ own, global_authored ].each do |target|
      get new_jjaek_comment_group_hide_path(jjaek, target)
      expect(response).to redirect_to(root_path)
      post jjaek_comment_group_hides_path(jjaek, target), params: { moderation_action: { public_reason: "other" } }
      expect(response).to redirect_to(root_path)
    end
    get new_jjaek_comment_group_restoration_path(jjaek, own_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_restorations_path(jjaek, own_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_comment_group_restoration_path(jjaek, platform_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_restorations_path(jjaek, platform_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    group_admin.update!(global_admin: true)
    get new_jjaek_comment_group_hide_path(jjaek, comment)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_hides_path(jjaek, comment), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_comment_group_restoration_path(jjaek, group_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_restorations_path(jjaek, group_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
  end

  it "preserves inactive restoration and operation-suspension boundaries for Group actions" do
    hidden_before_closure = jjaek.comments.create!(user: comment_author, content: "COMMENT HIDDEN BEFORE CLOSURE")
    hide = create_hide!(hidden_before_closure, actor: group_admin, authority: "group")
    inactive_target = jjaek.comments.create!(user: comment_author, content: "INACTIVE COMMENT HIDE TARGET")
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    sign_in group_admin

    get new_jjaek_comment_group_hide_path(jjaek, inactive_target)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_hides_path(jjaek, inactive_target), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_comment_group_restoration_path(jjaek, hidden_before_closure)
    expect(response).to have_http_status(:ok)
    post jjaek_comment_group_restorations_path(jjaek, hidden_before_closure), params: { moderation_action: { public_reason: "Resolved" } }
    expect(response).to redirect_to(anchored_jjaek_path(hidden_before_closure))
    expect(ModerationAction.find_by!(reversal_of: hide)).to be_group_authority

    suspended_group = Group.create!(
      lifecycle_status: :active,
      group_admin:,
      name: "Suspended comment action group",
      group_type: :private_group
    )
    suspended_group.group_memberships.create!(user: parent_author, status: :active)
    suspended_group.group_memberships.create!(user: comment_author, status: :active)
    suspended_jjaek = parent_author.jjaeks.create!(
      group: suspended_group,
      content: "SUSPENDED COMMENT ACTION PARENT"
    )
    suspended_visible = suspended_jjaek.comments.create!(
      user: comment_author,
      content: "SUSPENDED COMMENT HIDE TARGET"
    )
    suspended_hidden = suspended_jjaek.comments.create!(
      user: comment_author,
      content: "SUSPENDED COMMENT RESTORE TARGET"
    )
    create_hide!(suspended_hidden, actor: group_admin, authority: "group")
    suspended_group.update!(operation_suspended_at: Time.current)

    get new_jjaek_comment_group_hide_path(suspended_jjaek, suspended_visible)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_hides_path(suspended_jjaek, suspended_visible), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_jjaek_comment_group_restoration_path(suspended_jjaek, suspended_hidden)
    expect(response).to redirect_to(root_path)
    post jjaek_comment_group_restorations_path(suspended_jjaek, suspended_hidden), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
  end

  it "renders platform Action pages with context and entered values when services fail" do
    sign_in admin
    hide_service = instance_double(Comments::Hide)
    allow(Comments::Hide).to receive(:new).and_return(hide_service)
    allow(hide_service).to receive(:call!).and_raise(Comments::Hide::InvalidState)

    post admin_jjaek_comment_hides_path(jjaek, comment), params: {
      moderation_action: { public_reason: "other", internal_note: "Keep platform comment hide note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-comment-moderation-context]").text).to include(comment_author.name, "COMMENT ACTION TARGET", "COMMENT ACTION PARENT")
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep platform comment hide note")
    expect(comment.reload).not_to be_hidden

    hide = create_hide!(comment, actor: admin, authority: "platform", internal_note: "Current platform comment hide")
    restore_service = instance_double(Comments::Restore)
    allow(Comments::Restore).to receive(:new).and_return(restore_service)
    allow(restore_service).to receive(:call!).and_raise(Comments::Restore::InvalidState)

    post admin_jjaek_comment_restorations_path(jjaek, comment), params: {
      moderation_action: { public_reason: "Retry platform comment restore", internal_note: "Keep platform comment restore note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-comment-moderation-context]").text).to include(comment_author.name, "COMMENT ACTION TARGET", "COMMENT ACTION PARENT")
    expect(page.at_css("[data-current-hide-action-id='#{hide.id}']").text).to include("Current platform comment hide")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry platform comment restore")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep platform comment restore note")
    expect(comment.reload).to be_hidden
  end

  it "renders Group Action pages with context and entered values when services fail" do
    sign_in group_admin
    hide_service = instance_double(Comments::Hide)
    allow(Comments::Hide).to receive(:new).and_return(hide_service)
    allow(hide_service).to receive(:call!).and_raise(Comments::Hide::InvalidState)

    post jjaek_comment_group_hides_path(jjaek, comment), params: {
      moderation_action: { public_reason: "other", internal_note: "Keep group comment hide note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-comment-moderation-context]").text).to include(comment_author.name, group.name, "COMMENT ACTION TARGET")
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep group comment hide note")
    expect(comment.reload).not_to be_hidden

    hide = create_hide!(comment, actor: group_admin, authority: "group", internal_note: "Current group comment hide")
    restore_service = instance_double(Comments::Restore)
    allow(Comments::Restore).to receive(:new).and_return(restore_service)
    allow(restore_service).to receive(:call!).and_raise(Comments::Restore::InvalidState)

    post jjaek_comment_group_restorations_path(jjaek, comment), params: {
      moderation_action: { public_reason: "Retry group comment restore", internal_note: "Keep group comment restore note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-comment-moderation-context]").text).to include(comment_author.name, group.name, "COMMENT ACTION TARGET")
    expect(page.at_css("[data-current-hide-action-id='#{hide.id}']").text).to include("Current group comment hide")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry group comment restore")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep group comment restore note")
    expect(comment.reload).to be_hidden
  end

  it "does not recognize the four removed legacy PATCH routes" do
    expect {
      Rails.application.routes.recognize_path("/admin/jjaeks/#{jjaek.id}/comments/#{comment.id}/hide", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/admin/jjaeks/#{jjaek.id}/comments/#{comment.id}/restore", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/jjaeks/#{jjaek.id}/comments/#{comment.id}/hide", method: :patch)
    }.to raise_error(ActionController::RoutingError)
    expect {
      Rails.application.routes.recognize_path("/jjaeks/#{jjaek.id}/comments/#{comment.id}/restore", method: :patch)
    }.to raise_error(ActionController::RoutingError)
  end
end
