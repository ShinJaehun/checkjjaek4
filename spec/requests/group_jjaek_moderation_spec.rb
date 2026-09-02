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
      expect(response.body).to include(%(action="#{hide_jjaek_path(jjaek)}"))

      patch hide_jjaek_path(jjaek), params: {
        moderation_action: { public_reason: "other", internal_note: "Not accepted" }
      }

      expect(jjaek.reload).to be_hidden
      expect(jjaek.current_hide_action).to have_attributes(
        actor: group_admin,
        public_reason: "other",
        moderation_authority: "group",
        internal_note: nil
      )

      get jjaek_path(jjaek)
      expected_title = jjaek.book.present? ? "동아리 관리자에 의해 숨겨진 책짹입니다." : "동아리 관리자에 의해 숨겨진 짹입니다."
      expect(response.body).to include(expected_title, "기타", %(action="#{restore_jjaek_path(jjaek)}"))
    end
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
    Jjaeks::Hide.new(target, actor: group_admin, public_reason: "other").call!
    hide = target.current_hide_action
    group.transfer_admin_to!(current_admin, by: group_admin)
    group_admin.update!(global_admin: true)
    sign_in current_admin

    get jjaek_path(target)
    expect(response.body).to include("동아리 관리자에 의해 숨겨진 짹입니다.", %(action="#{restore_jjaek_path(target)}"))
    expect(hide.reload).to be_group_authority

    patch restore_jjaek_path(target), params: {
      moderation_action: { public_reason: "Resolved", internal_note: "Not accepted" }
    }

    expect(target.reload).not_to be_hidden
    expect(target.moderation_actions.action_type_restore.sole).to have_attributes(
      actor: current_admin,
      public_reason: "Resolved",
      moderation_authority: "group",
      internal_note: nil,
      reversal_of: hide
    )
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
