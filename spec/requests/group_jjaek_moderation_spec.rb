require "rails_helper"

RSpec.describe "Group Jjaek moderation", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "group-jjaek-moderator@example.com", password: "password123!") }
  let!(:author) { User.create!(name: "Author", email: "group-jjaek-moderation-author@example.com", password: "password123!") }
  let!(:global_author) { User.create!(name: "Global author", email: "group-jjaek-moderation-global@example.com", password: "password123!", global_admin: true) }
  let!(:book) { Book.create!(title: "Moderated book", authors_text: "Author") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Moderated group", group_type: :private_group) }

  before do
    group.group_memberships.create!(user: author, status: :active)
    sign_in group_admin
  end

  it "hides group jjaeks and group book jjaeks with group-admin attribution" do
    jjaeks = [
      author.jjaeks.create!(group:, content: "Group Jjaek"),
      author.jjaeks.create!(group:, book:, content: "Group Book Jjaek")
    ]

    jjaeks.each do |jjaek|
      get jjaek_path(jjaek)
      expect(response.body).to include(
        %(action="#{hide_jjaek_path(jjaek)}"),
        "내부 메모",
        "선택 입력 · 동아리 운영자에게만 표시됩니다."
      )

      patch hide_jjaek_path(jjaek), params: {
        moderation_action: { public_reason: "other", internal_note: "Not accepted" }
      }

      expect(jjaek.reload).to be_hidden
      expect(jjaek.current_hide_action).to have_attributes(
        actor: group_admin,
        public_reason: "other",
        moderation_authority: "group",
        internal_note: "Not accepted"
      )

      get jjaek_path(jjaek)
      expected_title = jjaek.book.present? ? "동아리 관리자에 의해 숨겨진 책짹입니다." : "동아리 관리자에 의해 숨겨진 짹입니다."
      expect(response.body).to include(expected_title, "기타", "내부 메모", "Not accepted", %(action="#{restore_jjaek_path(jjaek)}"), %(id="group_moderation_history"))
      detail = Nokogiri::HTML(response.body)
      expect(detail.css('#group_moderation_history [data-role="internal-note"]').map(&:text).join).to include("Not accepted")
      expect(detail.text.scan("Not accepted").size).to eq(1)
      expect(detail.at_css(%(form[action="#{restore_jjaek_path(jjaek)}"] textarea[name="moderation_action[internal_note]"]))).to be_present
    end
  end

  it "shows the complete group-origin moderation lifecycle in chronological order after restore" do
    global_admin = User.create!(name: "Platform admin", email: "group-history-platform@example.com", password: "password123!", global_admin: true)
    target = author.jjaeks.create!(group:, content: "History target")

    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other", internal_note: "FIRST GROUP NOTE").call!
    Jjaeks::Restore.new(target, actor: group_admin, public_reason: "First restore", internal_note: "").call!
    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "spam_advertising", internal_note: "SECOND GROUP NOTE").call!
    Jjaeks::Restore.new(target, actor: group_admin, public_reason: "Second restore", internal_note: "RESTORE GROUP NOTE").call!
    Jjaeks::Hide.new(target, actor: global_admin, public_reason: "service_disruption", internal_note: "PLATFORM HIDE NOTE").call!
    Jjaeks::Restore.new(target, actor: global_admin, public_reason: "Platform restore", internal_note: "PLATFORM RESTORE NOTE").call!

    get jjaek_path(target)

    expect(response).to have_http_status(:ok)
    history = Nokogiri::HTML(response.body).at_css("#group_moderation_history")
    expect(history).to be_present
    entries = history.css("li")
    expect(entries.size).to eq(4)
    entry_texts = entries.map(&:text).map(&:squish)
    group_actions = target.moderation_actions.where(moderation_authority: "group").order(created_at: :asc, id: :asc)
    expect(entry_texts[0]).to include("Group admin님이 #{I18n.l(group_actions[0].created_at, format: :short)}에 숨김", "사유: 기타", "내부 메모 FIRST GROUP NOTE")
    expect(entry_texts[1]).to include("Group admin님이 #{I18n.l(group_actions[1].created_at, format: :short)}에 복구함", "사유: First restore")
    expect(entry_texts[2]).to include("Group admin님이 #{I18n.l(group_actions[2].created_at, format: :short)}에 숨김", "사유: 스팸·광고", "내부 메모 SECOND GROUP NOTE")
    expect(entry_texts[3]).to include("Group admin님이 #{I18n.l(group_actions[3].created_at, format: :short)}에 복구함", "사유: Second restore", "내부 메모 RESTORE GROUP NOTE")
    expect(entries[0].at_css('[data-role="internal-note"]')).to be_present
    expect(entries[1].at_css('[data-role="internal-note"]')).to be_nil
    expect(history.text).not_to include("PLATFORM HIDE NOTE")
    expect(history.text).not_to include("PLATFORM RESTORE NOTE")
    expect(history.text).not_to include("Platform restore")
    expect(history.text).not_to include("서비스 운영 방해")
    expect(target.reload).not_to be_hidden
  end

  it "shows group-origin hidden reading context to members without exposing the body or mutations" do
    member = User.create!(name: "Member", email: "hidden-group-card-member@example.com", password: "password123!")
    global_admin = User.create!(name: "Platform admin", email: "hidden-group-card-platform@example.com", password: "password123!", global_admin: true)
    group.group_memberships.create!(user: member, status: :active)
    target = author.jjaeks.create!(group:, content: "Hidden group card target")
    target.likes.create!(user: author)
    target.comments.create!(user: author, content: "Existing hidden comment")
    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other", internal_note: "PRIVATE GROUP NOTE").call!
    comments_panel_id = "comments_panel_group_jjaek_#{target.id}"

    [ group_admin, global_admin ].each do |moderator|
      sign_in moderator
      get group_path(group)
      moderator_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{target.id}")
      expect(moderator_card.text).to include("좋아요 1개", "댓글 1개", "댓글 보기", "글 보기")
      expect(moderator_card.at_css(%(a[href="#{jjaek_comments_path(target, comments_context: :group)}"]))).to be_present
      expect(moderator_card.at_css(%(a[href="#{jjaek_path(target)}"]))).to be_present
      expect(moderator_card.at_css("##{comments_panel_id}")).to be_present
      expect(moderator_card.at_css(%(form[action="#{jjaek_like_path(target)}"]))).to be_nil
      expect(moderator_card.text).not_to include("다시짹")

      get jjaek_comments_path(target, comments_context: :group),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(target="#{comments_panel_id}"), "Existing hidden comment")
      expect(response.body).not_to include(%(action="#{jjaek_comments_path(target)}"))
    end

    sign_in member
    get group_path(group)
    member_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{target.id}")
    expect(member_card).to be_present
    expect(member_card.text).to include("동아리 관리자에 의해 숨겨진 짹입니다.", "기타", "좋아요 1개", "댓글 1개", "댓글 보기", "글 보기")
    expect(member_card.text).not_to include("Hidden group card target", "PRIVATE GROUP NOTE")
    expect(member_card.at_css(%(a[href="#{jjaek_comments_path(target, comments_context: :group)}"]))).to be_present
    expect(member_card.at_css(%(a[href="#{jjaek_path(target)}"]))).to be_present
    expect(member_card.at_css("##{comments_panel_id}")).to be_present
    expect(member_card.at_css(%(form[action="#{jjaek_like_path(target)}"]))).to be_nil
    expect(member_card.text).not_to include("다시짹")

    get jjaek_comments_path(target, comments_context: :group),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="#{comments_panel_id}"), "Existing hidden comment")
    expect(response.body).not_to include(%(action="#{jjaek_comments_path(target)}"))

    get jjaek_path(target)
    expect(response).to have_http_status(:ok)
    detail = Nokogiri::HTML(response.body)
    expect(detail.text).to include("동아리 관리자에 의해 숨겨진 짹입니다.", "기타", "Existing hidden comment")
    expect(detail.text).not_to include("Hidden group card target", "PRIVATE GROUP NOTE", "운영 이력")
    expect(detail.at_css(%(form[action="#{jjaek_comments_path(target)}"]))).to be_nil
    expect(detail.at_css(%(form[action="#{jjaek_like_path(target)}"]))).to be_nil
  end

  it "keeps group and platform authority boundaries for hidden Jjaeks" do
    outsider = User.create!(name: "Outsider", email: "hidden-group-outsider@example.com", password: "password123!")
    global_admin = User.create!(name: "Platform admin", email: "hidden-group-platform@example.com", password: "password123!", global_admin: true)
    group_hidden = author.jjaeks.create!(group:, content: "GROUP HIDDEN BODY")
    platform_hidden = author.jjaeks.create!(group:, content: "PLATFORM HIDDEN BODY")
    Jjaeks::Hide.new(group_hidden, actor: group_admin, public_reason: "other").call!
    Jjaeks::Hide.new(platform_hidden, actor: global_admin, public_reason: "other").call!
    sign_out group_admin
    group_admin.update!(global_admin: true)
    global_admin.update!(global_admin: false)

    sign_in outsider
    get group_path(group)
    expect(response).to have_http_status(:not_found)
    get jjaek_path(group_hidden)
    expect(response).to have_http_status(:redirect)

    member = User.create!(name: "Member", email: "hidden-platform-member@example.com", password: "password123!")
    group.group_memberships.create!(user: member, status: :active)
    sign_in member
    get group_path(group)
    expect(response.body).to include(%(id="jjaek_#{group_hidden.id}"))
    expect(response.body).to include(%(id="jjaek_#{platform_hidden.id}"))
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 짹입니다.")
    expect(response.body).not_to include("PLATFORM HIDDEN BODY")

    get jjaek_path(platform_hidden)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 짹입니다.")
    expect(response.body).not_to include("PLATFORM HIDDEN BODY")
  end

  it "allows inactive group moderation but rejects ineligible hide targets" do
    inactive_group = Group.create!(
      lifecycle_status: :inactive,
      group_admin:,
      name: "Inactive group",
      group_type: :private_group,
      closure_reason: "Closed",
      closed_at: Time.current
    )
    inactive_target = author.jjaeks.create!(group: inactive_group, content: "Inactive target")
    patch hide_jjaek_path(inactive_target), params: { moderation_action: { public_reason: "other" } }
    expect(inactive_target.reload).to be_hidden
    patch restore_jjaek_path(inactive_target), params: { moderation_action: { public_reason: "Resolved" } }
    expect(inactive_target.reload).not_to be_hidden

    other_group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Other group", group_type: :public_group)
    pending_group = Group.create!(group_admin:, name: "Pending group", group_type: :private_group, application_purpose: "Pending")
    suspended_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Suspended group", group_type: :private_group, operation_suspended_at: Time.current)
    targets = [
      group_admin.jjaeks.create!(group:, content: "Own target"),
      global_author.jjaeks.create!(group:, content: "Global target"),
      author.jjaeks.create!(content: "Personal target"),
      author.jjaeks.create!(group: other_group, content: "Other group target"),
      author.jjaeks.create!(group: pending_group, content: "Pending target"),
      author.jjaeks.create!(group: suspended_group, content: "Suspended target")
    ]

    targets.each do |target|
      expect {
        patch hide_jjaek_path(target), params: { moderation_action: { public_reason: "other" } }
      }.not_to change(ModerationAction, :count)
      expect(target.reload).not_to be_hidden
    end
  end

  it "restores a hide from the same group authority after an admin transfer" do
    current_admin = User.create!(name: "New admin", email: "new-group-jjaek-moderator@example.com", password: "password123!")
    group.group_memberships.create!(user: current_admin, status: :active)
    target = author.jjaeks.create!(group:, content: "Transferred moderation")
    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other", internal_note: "Previous admin note").call!
    hide = target.current_hide_action
    group.transfer_admin_to!(current_admin, by: group_admin)

    sign_in group_admin
    get jjaek_path(target)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("동아리 관리자에 의해 숨겨진 짹입니다.")
    expect(response.body).not_to include("Transferred moderation")
    expect(response.body).not_to include("Previous admin note")
    expect(response.body).not_to include(%(id="group_moderation_history"))
    expect(response.body).not_to include(%(action="#{restore_jjaek_path(target)}"))

    sign_in current_admin

    get jjaek_path(target)
    expect(response.body).to include("동아리 관리자에 의해 숨겨진 짹입니다.", "Previous admin note", %(action="#{restore_jjaek_path(target)}"))
    expect(hide.reload).to be_group_authority

    patch restore_jjaek_path(target), params: {
      moderation_action: { public_reason: "Resolved", internal_note: "Not accepted" }
    }

    expect(target.reload).not_to be_hidden
    expect(target.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: current_admin,
      public_reason: "Resolved",
      moderation_authority: "group",
      internal_note: "Not accepted",
      reversal_of: hide
    )

    get jjaek_path(target)
    history = Nokogiri::HTML(response.body).at_css("#group_moderation_history")
    expect(history.text).to include("Group admin", "Previous admin note", "New admin", "Resolved", "Not accepted")
  end

  it "limits group-origin internal notes to the current group admin and global admins" do
    member = User.create!(name: "Member", email: "group-note-member@example.com", password: "password123!")
    other_group_admin = User.create!(name: "Other admin", email: "other-group-note-admin@example.com", password: "password123!")
    global_admin = User.create!(name: "Global admin", email: "global-group-note-admin@example.com", password: "password123!", global_admin: true)
    group.group_memberships.create!(user: member, status: :active)
    other_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Other note group", group_type: :private_group)
    other_group.group_memberships.create!(user: author, status: :active)
    target = author.jjaeks.create!(group:, content: "Group note target")
    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other", internal_note: "GROUP ORIGIN NOTE").call!

    sign_in author
    get jjaek_path(target)
    expect(response.body).not_to include("운영 이력")
    expect(response.body).not_to include("GROUP ORIGIN NOTE")

    sign_in member
    get jjaek_path(target)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("GROUP ORIGIN NOTE")
    expect(response.body).not_to include(%(id="group_moderation_history"))

    sign_in other_group_admin
    get jjaek_path(target)
    expect(response).to have_http_status(:not_found)

    sign_in global_admin
    get jjaek_path(target)
    expect(response.body).to include("GROUP ORIGIN NOTE")
    expect(response.body).not_to include(%(id="group_moderation_history"))

    sign_in group_admin
    patch restore_jjaek_path(target), params: { moderation_action: { public_reason: "Visible again" } }

    sign_in author
    get jjaek_path(target)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(id="group_moderation_history"))

    sign_in member
    get jjaek_path(target)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(id="group_moderation_history"))
  end

  it "rejects restore outside the current group authority boundary" do
    global_admin = User.create!(name: "Platform admin", email: "platform-group-jjaek-moderator@example.com", password: "password123!", global_admin: true)
    global_hide = author.jjaeks.create!(group:, content: "Global hide")
    Jjaeks::Hide.new(global_hide, actor: global_admin, public_reason: "other").call!
    global_admin.update!(global_admin: false)

    get jjaek_path(global_hide)
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 짹입니다.")
    expect(response.body).not_to include(%(action="#{restore_jjaek_path(global_hide)}"))
    expect(global_hide.current_hide_action).to be_platform_authority

    other_group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Other restore group", group_type: :public_group)
    pending_group = Group.create!(group_admin:, name: "Pending restore group", group_type: :private_group, application_purpose: "Pending")
    suspended_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Suspended restore group", group_type: :private_group, operation_suspended_at: Time.current)
    own_target = group_admin.jjaeks.create!(group:, content: "Own hidden target")
    other_target = author.jjaeks.create!(group: other_group, content: "Other hidden target")
    pending_target = author.jjaeks.create!(group: pending_group, content: "Pending hidden target")
    suspended_target = author.jjaeks.create!(group: suspended_group, content: "Suspended hidden target")

    [ own_target, other_target, pending_target, suspended_target ].each do |target|
      target.update!(hidden_at: Time.current)
      ModerationAction.create!(target:, actor: author, action_type: :hide, public_reason: "other", moderation_authority: "group")
    end

    [ global_hide, own_target, other_target, pending_target, suspended_target ].each do |target|
      expect {
        patch restore_jjaek_path(target), params: { moderation_action: { public_reason: "Blocked" } }
      }.not_to change(ModerationAction, :count)
      expect(target.reload).to be_hidden
    end
  end

  it "requires a public reason for group hide and restore" do
    target = author.jjaeks.create!(group:, content: "Reason target")

    expect {
      patch hide_jjaek_path(target), params: { moderation_action: { public_reason: "" } }
    }.not_to change(ModerationAction, :count)
    expect(target.reload).not_to be_hidden

    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other").call!
    expect {
      patch restore_jjaek_path(target), params: { moderation_action: { public_reason: "" } }
    }.not_to change(ModerationAction, :count)
    expect(target.reload).to be_hidden
  end
end
