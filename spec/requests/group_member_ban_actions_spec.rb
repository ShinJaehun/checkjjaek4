require "rails_helper"

RSpec.describe "Group member ban actions", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "ban-action-admin@example.com", password: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "ban-action-member@example.com", password: "password123!") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }
  let!(:membership) { group.group_memberships.create!(user: member, status: :active) }

  it "links to a ban page without an inline reason form" do
    sign_in group_admin

    get group_members_path(group)
    page = Nokogiri::HTML(response.body)
    management = page.at_css("#group_membership_#{membership.id} [data-member-management]")
    expect(management.at_css("a[href='#{new_group_group_membership_member_ban_path(group, membership)}']")).to be_present
    expect(management.at_css("[data-member-action='ban_from_group'] form")).to be_nil

    get new_group_group_membership_member_ban_path(group, membership)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(
      group.name,
      member.name,
      "참여 중",
      "정상 활동",
      "회원을 동아리에서 내보내고 이용 제한을 해제하기 전까지 다시 참여하지 못하게 합니다."
    )
    form = page.at_css("form[action='#{group_group_membership_member_bans_path(group, membership)}']")
    expect(form.at_css("textarea[name='moderation_action[public_reason]'][required]")).to be_present
    expect(form.at_css("textarea[name='moderation_action[internal_note]']")).to be_present
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
  end

  it "bans the membership with the existing audit and notification source" do
    sign_in group_admin

    post group_group_membership_member_bans_path(group, membership), params: {
      moderation_action: { public_reason: "Community rule", internal_note: "Case 10" }
    }

    expect(response).to redirect_to(group_members_path(group))
    expect(GroupMembership.exists?(membership.id)).to be(false)
    ban = group.group_member_bans.find_by!(user: member)
    action = ban.current_ban_action
    expect(action).to have_attributes(
      actor: group_admin,
      action_type: "ban_from_group",
      public_reason: "Community rule",
      internal_note: "Case 10"
    )
    expect(Notification.find_by!(notifiable: action, action: :group_member_banned)).to have_attributes(recipient: member)

    get group_members_path(group)
    page = Nokogiri::HTML(response.body)
    ban_card = page.at_css("#group_member_ban_#{ban.id}")
    expect(ban_card.text).to include(member.name, "동아리 이용 제한", "Community rule")
    expect(ban_card.at_css("a[href='#{new_group_group_member_ban_restoration_path(group, ban)}']")).to be_present
    expect(ban_card.at_css("form")).to be_nil
    expect(page.at_css("#membership-operations-history [data-ban-history-entry='ban_from_group']")).to be_present
  end

  it "shows the current ban on restoration and creates a linked reversal without restoring membership" do
    ban = GroupMemberBans::Ban.new(
      membership,
      actor: group_admin,
      public_reason: "Original reason",
      internal_note: "Original note"
    ).call!
    original_action = ban.current_ban_action
    sign_in group_admin

    get new_group_group_member_ban_restoration_path(group, ban)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "동아리 이용 제한", "현재 이용 제한 조치")
    ban_entry = page.at_css("[data-ban-history-entry='ban_from_group']")
    expect(ban_entry.text).to include(group_admin.name, member.name, "Original reason", "Original note")
    form = page.at_css("form[action='#{group_group_member_ban_restorations_path(group, ban)}']")
    expect(form.at_css("textarea[name='moderation_action[public_reason]'][required]")).to be_present
    expect(form.at_css("textarea[name='moderation_action[internal_note]']")).to be_present

    post group_group_member_ban_restorations_path(group, ban), params: {
      moderation_action: { public_reason: "Reviewed", internal_note: "Resolved" }
    }

    expect(response).to redirect_to(group_members_path(group))
    expect(GroupMemberBan.exists?(ban.id)).to be(false)
    expect(group.group_memberships.exists?(user: member)).to be(false)
    restoration = ModerationAction.find_by!(reversal_of: original_action)
    expect(restoration).to have_attributes(
      actor: group_admin,
      action_type: "unban_from_group",
      public_reason: "Reviewed",
      internal_note: "Resolved"
    )
    expect(Notification.find_by!(notifiable: restoration, action: :group_member_unbanned)).to have_attributes(recipient: member)

    get group_members_path(group)
    history = Nokogiri::HTML(response.body).at_css("#membership-operations-history")
    expect(history.at_css("[data-ban-history-entry='ban_from_group']")).to be_present
    expect(history.at_css("[data-ban-history-entry='unban_from_group']")).to be_present
  end

  it "denies ban and unban pages and mutations to users who are not this group's admin" do
    global_admin = User.create!(name: "Global admin", email: "ban-action-global@example.com", password: "password123!", global_admin: true)

    [ member, global_admin ].each do |actor|
      sign_in actor
      get new_group_group_membership_member_ban_path(group, membership)
      expect(response).to redirect_to(root_path)
      post group_group_membership_member_bans_path(group, membership), params: {
        moderation_action: { public_reason: "Blocked" }
      }
      expect(response).to redirect_to(root_path)
    end
    expect(membership.reload).to be_persisted

    ban = GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Original").call!
    [ member, global_admin ].each do |actor|
      sign_in actor
      get new_group_group_member_ban_restoration_path(group, ban)
      expect(response).to redirect_to(root_path)
      post group_group_member_ban_restorations_path(group, ban), params: {
        moderation_action: { public_reason: "Blocked" }
      }
      expect(response).to redirect_to(root_path)
    end
    expect(ban.reload).to be_persisted
  end

  it "allows a global admin only when that user is this group's admin" do
    global_group_admin = User.create!(name: "Both roles", email: "ban-action-both@example.com", password: "password123!", global_admin: true)
    managed_group = Group.create!(lifecycle_status: :active, group_admin: global_group_admin, name: "Managed readers", group_type: :public_group)
    managed_membership = managed_group.group_memberships.create!(user: member, status: :active)
    sign_in global_group_admin

    get new_group_group_membership_member_ban_path(managed_group, managed_membership)
    expect(response).to have_http_status(:ok)
    post group_group_membership_member_bans_path(managed_group, managed_membership), params: {
      moderation_action: { public_reason: "Group rule" }
    }
    expect(response).to redirect_to(group_members_path(managed_group))

    ban = managed_group.group_member_bans.find_by!(user: member)
    get new_group_group_member_ban_restoration_path(managed_group, ban)
    expect(response).to have_http_status(:ok)
    post group_group_member_ban_restorations_path(managed_group, ban), params: {
      moderation_action: { public_reason: "Restriction lifted" }
    }
    expect(response).to redirect_to(group_members_path(managed_group))
    expect(GroupMemberBan.exists?(ban.id)).to be(false)
    expect(managed_group.group_memberships.exists?(user: member)).to be(false)
  end

  it "uses the action policies to reject new and create in invalid states" do
    approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Approval", group_type: :approval_group)
    pending_membership = approval_group.group_memberships.create!(user: member, status: :pending)
    sign_in group_admin

    get new_group_group_membership_member_ban_path(approval_group, pending_membership)
    expect(response).to redirect_to(root_path)
    post group_group_membership_member_bans_path(approval_group, pending_membership), params: {
      moderation_action: { public_reason: "Not active" }
    }
    expect(response).to redirect_to(root_path)
    expect(pending_membership.reload).to be_pending

    ban = GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Original").call!
    group.update!(operation_suspended_at: Time.current)
    get new_group_group_member_ban_restoration_path(group, ban)
    expect(response).to redirect_to(root_path)
    post group_group_member_ban_restorations_path(group, ban), params: {
      moderation_action: { public_reason: "Blocked" }
    }
    expect(response).to redirect_to(root_path)
    expect(ban.reload).to be_persisted
  end

  it "keeps ban inputs and membership context when the service fails" do
    sign_in group_admin
    failing_service = instance_double(GroupMemberBans::Ban)
    allow(GroupMemberBans::Ban).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(GroupMemberBans::Ban::InvalidState)

    post group_group_membership_member_bans_path(group, membership), params: {
      moderation_action: { public_reason: "Retry reason", internal_note: "Retry note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "참여 중", "정상 활동")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry reason")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Retry note")
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
    expect(membership.reload).to be_persisted
  end

  it "keeps unban inputs and the same current ban action when the service fails" do
    ban = GroupMemberBans::Ban.new(
      membership,
      actor: group_admin,
      public_reason: "Original reason",
      internal_note: "Original note"
    ).call!
    sign_in group_admin
    failing_service = instance_double(GroupMemberBans::Unban)
    allow(GroupMemberBans::Unban).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(GroupMemberBans::Unban::InvalidState)

    post group_group_member_ban_restorations_path(group, ban), params: {
      moderation_action: { public_reason: "Retry reason", internal_note: "Retry note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, member.name, "현재 이용 제한 조치")
    entry = page.at_css("[data-ban-history-entry='ban_from_group']")
    expect(entry.text).to include("Original reason", "Original note")
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry reason")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Retry note")
    expect(page.at_css("a[href='#{group_members_path(group)}']")).to be_present
    expect(ban.reload).to be_persisted
  end

  it "does not route the legacy create and destroy endpoints" do
    expect {
      Rails.application.routes.recognize_path("/groups/#{group.id}/group_member_bans", method: :post)
    }.to raise_error(ActionController::RoutingError)

    expect {
      Rails.application.routes.recognize_path("/groups/#{group.id}/group_member_bans/1", method: :delete)
    }.to raise_error(ActionController::RoutingError)
  end
end
