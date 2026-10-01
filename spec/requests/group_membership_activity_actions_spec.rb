require "rails_helper"

RSpec.describe "Group membership activity actions", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "activity-action-admin@example.com", password: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "activity-action-member@example.com", password: "password123!") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }
  let!(:membership) { group.group_memberships.create!(user: member, status: :active) }

  it "links to a suspension page without an inline reason form" do
    sign_in group_admin

    get group_members_path(group)
    page = Nokogiri::HTML(response.body)
    management = page.at_css("#group_membership_#{membership.id} [data-member-management]")
    expect(management.at_css("a[href='#{new_group_group_membership_activity_suspension_path(group, membership)}']")).to be_present
    expect(management.at_css("[data-member-action='suspend_activity'] form")).to be_nil
    expect(management.at_css("[data-member-action='restore_activity']")).to be_nil

    get new_group_group_membership_activity_suspension_path(group, membership)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "참여 중", "정상 활동", "회원 자격은 유지하고 동아리 활동만 정지합니다.")
    form = page.at_css("form[action='#{group_group_membership_activity_suspensions_path(group, membership)}']")
    expect(form.at_css("textarea[name='moderation_action[public_reason]'][required]")).to be_present
    expect(form.at_css("textarea[name='moderation_action[internal_note]']")).to be_present
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
  end

  it "suspends activity with the existing audit and notification source" do
    sign_in group_admin

    post group_group_membership_activity_suspensions_path(group, membership), params: {
      moderation_action: { public_reason: "Community rule", internal_note: "Case 10" }
    }

    expect(response).to redirect_to(group_members_path(group))
    expect(membership.reload).to be_activity_suspended
    action = ModerationAction.find_by!(target: membership, action_type: :suspend_activity)
    expect(action).to have_attributes(actor: group_admin, public_reason: "Community rule", internal_note: "Case 10")
    expect(Notification.find_by!(notifiable: action, action: :group_member_activity_suspended)).to have_attributes(recipient: member)

    get group_members_path(group)
    page = Nokogiri::HTML(response.body)
    member_card = page.at_css("#group_membership_#{membership.id}")
    expect(member_card.text).to include("동아리 활동 정지", "Community rule")
    expect(member_card.at_css("a[href='#{new_group_group_membership_activity_restoration_path(group, membership)}']")).to be_present
    expect(member_card.at_css("[data-member-action='restore_activity'] form")).to be_nil
    expect(member_card.at_css("[data-member-action='suspend_activity']")).to be_nil
  end

  it "safely redirects stale suspension pages and submissions after the membership is gone" do
    membership.destroy!
    sign_in group_admin

    moderation_action_count = ModerationAction.count
    notification_count = Notification.count
    membership_count = GroupMembership.count

    get new_group_group_membership_activity_suspension_path(group, membership)
    expect(response).to redirect_to(group_members_path(group))
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.stale_action"))

    post group_group_membership_activity_suspensions_path(group, membership), params: {
      moderation_action: { public_reason: "Stale suspension" }
    }
    expect(response).to redirect_to(group_members_path(group))
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.stale_action"))
    expect(GroupMembership.count).to eq(membership_count)
    expect(GroupMembership.exists?(membership.id)).to be(false)
    expect(ModerationAction.count).to eq(moderation_action_count)
    expect(Notification.count).to eq(notification_count)
  end

  it "shows the current suspension on restoration and creates a linked reversal" do
    GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Original reason", internal_note: "Original note").call!
    suspension = membership.current_activity_suspension_action
    sign_in group_admin

    get new_group_group_membership_activity_restoration_path(group, membership)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "동아리 활동 정지", "현재 정지 조치")
    suspension_entry = page.at_css("[data-activity-history-entry='suspend_activity']")
    expect(suspension_entry.text).to include(group_admin.name, member.name, "Original reason", "Original note")
    form = page.at_css("form[action='#{group_group_membership_activity_restorations_path(group, membership)}']")
    expect(form.at_css("textarea[name='moderation_action[public_reason]'][required]")).to be_present
    expect(form.at_css("textarea[name='moderation_action[internal_note]']")).to be_present

    post group_group_membership_activity_restorations_path(group, membership), params: {
      moderation_action: { public_reason: "Reviewed", internal_note: "Resolved" }
    }

    expect(response).to redirect_to(group_members_path(group))
    expect(membership.reload).to be_moderation_status_normal
    restoration = ModerationAction.find_by!(reversal_of: suspension)
    expect(restoration).to have_attributes(target: membership, actor: group_admin, action_type: "restore_activity", public_reason: "Reviewed", internal_note: "Resolved")
    expect(Notification.find_by!(notifiable: restoration, action: :group_member_activity_restored)).to have_attributes(recipient: member)
  end

  it "safely redirects stale restoration pages and submissions after the membership is gone" do
    GroupMemberships::SuspendActivity.new(
      membership,
      actor: group_admin,
      public_reason: "Original reason"
    ).call!
    membership.destroy!
    sign_in group_admin

    moderation_action_count = ModerationAction.count
    notification_count = Notification.count
    membership_count = GroupMembership.count

    get new_group_group_membership_activity_restoration_path(group, membership)
    expect(response).to redirect_to(group_members_path(group))
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.stale_action"))

    post group_group_membership_activity_restorations_path(group, membership), params: {
      moderation_action: { public_reason: "Stale restoration" }
    }
    expect(response).to redirect_to(group_members_path(group))
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.stale_action"))
    expect(GroupMembership.count).to eq(membership_count)
    expect(GroupMembership.exists?(membership.id)).to be(false)
    expect(ModerationAction.count).to eq(moderation_action_count)
    expect(Notification.count).to eq(notification_count)
  end

  it "denies new and create to users who are not this group's admin" do
    global_admin = User.create!(name: "Global admin", email: "activity-action-global@example.com", password: "password123!", global_admin: true)
    [ member, global_admin ].each do |actor|
      sign_in actor
      get new_group_group_membership_activity_suspension_path(group, membership)
      expect(response).to redirect_to(root_path)
      post group_group_membership_activity_suspensions_path(group, membership), params: { moderation_action: { public_reason: "Blocked" } }
      expect(response).to redirect_to(root_path)
    end
    expect(membership.reload).to be_moderation_status_normal

    GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Original").call!
    [ member, global_admin ].each do |actor|
      sign_in actor
      get new_group_group_membership_activity_restoration_path(group, membership)
      expect(response).to redirect_to(root_path)
      post group_group_membership_activity_restorations_path(group, membership), params: { moderation_action: { public_reason: "Blocked" } }
      expect(response).to redirect_to(root_path)
    end
    expect(membership.reload).to be_activity_suspended
  end

  it "allows a global admin only when that user is this group's admin" do
    global_group_admin = User.create!(name: "Both roles", email: "activity-action-both@example.com", password: "password123!", global_admin: true)
    managed_group = Group.create!(lifecycle_status: :active, group_admin: global_group_admin, name: "Managed readers", group_type: :public_group)
    managed_membership = managed_group.group_memberships.create!(user: member, status: :active)
    sign_in global_group_admin

    get new_group_group_membership_activity_suspension_path(managed_group, managed_membership)
    expect(response).to have_http_status(:ok)
    post group_group_membership_activity_suspensions_path(managed_group, managed_membership), params: {
      moderation_action: { public_reason: "Group rule" }
    }
    expect(response).to redirect_to(group_members_path(managed_group))
    expect(managed_membership.reload).to be_activity_suspended
  end

  it "uses the same membership policy for invalid new and create states" do
    sign_in group_admin
    get new_group_group_membership_activity_restoration_path(group, membership)
    expect(response).to redirect_to(root_path)
    post group_group_membership_activity_restorations_path(group, membership), params: { moderation_action: { public_reason: "Too soon" } }
    expect(response).to redirect_to(root_path)

    GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Original").call!
    get new_group_group_membership_activity_suspension_path(group, membership)
    expect(response).to redirect_to(root_path)
    post group_group_membership_activity_suspensions_path(group, membership), params: { moderation_action: { public_reason: "Again" } }
    expect(response).to redirect_to(root_path)
    expect(ModerationAction.where(target: membership, action_type: :suspend_activity).count).to eq(1)
  end

  it "keeps suspension inputs and target context when the service fails" do
    sign_in group_admin
    failing_service = instance_double(GroupMemberships::SuspendActivity)
    allow(GroupMemberships::SuspendActivity).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(GroupMemberships::SuspendActivity::InvalidState)

    post group_group_membership_activity_suspensions_path(group, membership), params: {
      moderation_action: { public_reason: "Retry reason", internal_note: "Retry note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "정상 활동")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry reason")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Retry note")
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
    expect(membership.reload).to be_moderation_status_normal
  end

  it "keeps restoration inputs and the same suspension entry when the service fails" do
    GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Original reason", internal_note: "Original note").call!
    sign_in group_admin
    failing_service = instance_double(GroupMemberships::RestoreActivity)
    allow(GroupMemberships::RestoreActivity).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(GroupMemberships::RestoreActivity::InvalidState)

    post group_group_membership_activity_restorations_path(group, membership), params: {
      moderation_action: { public_reason: "Retry reason", internal_note: "Retry note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "현재 정지 조치")
    entry = page.at_css("[data-activity-history-entry='suspend_activity']")
    expect(entry.text).to include("Original reason", "Original note")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry reason")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Retry note")
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
    expect(membership.reload).to be_activity_suspended
  end
end
